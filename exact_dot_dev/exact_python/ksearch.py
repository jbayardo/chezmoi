# /// script
# dependencies = ["azure-kusto-data", "sentence-transformers", "numpy", "pandas", "textual", "textual-dev", "pyperclip"]
# ///
import hashlib
import pickle
import tempfile
from azure.kusto.data import KustoClient, KustoConnectionStringBuilder
from azure.kusto.data.exceptions import KustoServiceError
from sentence_transformers import SentenceTransformer, util
import os
import json
import datetime

import torch

# Kusto cluster details
KUSTO_CLUSTER = "https://cbuild.kusto.windows.net"
KUSTO_DATABASE = "CloudBuildProd"


def create_kusto_client(on_update):
    on_update("Establishing Kusto connection")
    kcsb = KustoConnectionStringBuilder.with_az_cli_authentication(KUSTO_CLUSTER)
    return KustoClient(kcsb)


def fetch_kusto_queries(on_update, force_reload=False, recency_threshold_hrs=2):
    cache_file = os.path.join(tempfile.gettempdir(), "kusto_query_cache.json")
    previous_results = []

    on_update(f"Loading data from cache @ {cache_file}")
    try:
        if os.path.exists(cache_file):
            with open(cache_file, "r") as file:
                cached_data = json.load(file)
                last_run_time = cached_data.get("last_run_time")
                previous_results = cached_data.get("results", [])

                if (
                    last_run_time
                    and len(previous_results) > 0
                    and (
                        datetime.datetime.now()
                        - datetime.datetime.fromisoformat(last_run_time)
                    )
                    < datetime.timedelta(hours=recency_threshold_hrs)
                    and not force_reload
                ):
                    on_update(f"Loaded {len(previous_results)} queries from cache")
                    return previous_results
    except:
        on_update("Failed to load data from cache")
        pass

    on_update("Loading data from Kusto")
    query = """
    .show queries
    | where StartedOn > ago(30d)
    | where User startswith "jubayard"
    | where ClientActivityId startswith "KE.RunQuery" or ClientActivityId startswith "Kusto.Web.KWE.Query"
    | where not(Text startswith @'table("' and Text endswith @'"]')
    | where State == "Completed"
    | project ClientActivityId, StartedOn, Text
    | summarize arg_min(StartedOn, ClientActivityId) by Text
    """
    client = create_kusto_client(on_update)
    new_results = client.execute(KUSTO_DATABASE, query).primary_results[0]
    new_results = new_results.to_dict()["data"]

    combined_results = {}
    for result in previous_results:
        combined_results[result["ClientActivityId"]] = result

    for result in new_results:
        if combined_results.get(result["ClientActivityId"], None) is None:
            combined_results[result["ClientActivityId"]] = result
    final_results = list(combined_results.values())
    on_update(f"Loaded {len(final_results)} queries from Kusto")

    with open(cache_file, "w") as file:
        json.dump(
            {
                "last_run_time": datetime.datetime.now().isoformat(),
                "results": final_results,
            },
            file,
            default=str,
        )

    return final_results


def cache_embeddings(on_update, cache):
    cache_file = os.path.join(tempfile.gettempdir(), "embeddings_cache.torch")
    on_update("Storing embeddings into cache")
    torch.save(cache, cache_file)


def load_embeddings_from_cache(on_update):
    cache_file = os.path.join(tempfile.gettempdir(), "embeddings_cache.torch")
    on_update("Loading embeddings from cache")
    cache = {}
    if os.path.exists(cache_file):
        try:
            cache = torch.load(cache_file)
        except Exception as e:
            on_update(f"Failed to load embeddings from cache: {e}. Deleting cache.")
            os.remove(cache_file)
    return cache


def group_by_similarity(
    on_update, result, grouping_threshold=0.8, filter_threshold=0.9
):
    if not result:
        return []

    queries, timestamps = zip(*[(row["Text"], row["StartedOn"]) for row in result])

    embeddings_cache = load_embeddings_from_cache(on_update)

    n = len(queries)
    groups = []
    visited = [False] * n

    # Encode any queries that aren't cached
    queries_to_encode = []
    indices_to_encode = []

    for i in range(n):
        query = queries[i]
        cache_key = hashlib.md5(query.encode()).hexdigest()
        if cache_key not in embeddings_cache:
            queries_to_encode.append(query)
            indices_to_encode.append(i)

    if len(queries_to_encode) > 0:
        on_update("Loading embeddings model")
        model = SentenceTransformer("all-MiniLM-L6-v2")

        on_update(f"Computing embeddings for {len(queries_to_encode)} queries")
        embeddings_list = model.encode(queries_to_encode, convert_to_tensor=True)

        # Cache the newly computed embeddings
        for i, index in enumerate(indices_to_encode):
            cache_key = hashlib.md5(queries[index].encode()).hexdigest()
            embeddings_cache[cache_key] = embeddings_list[i]

        cache_embeddings(on_update, embeddings_cache)

    # Calculate cosine similarities between all embeddings
    embeddings_list = torch.stack(
        [embeddings_cache[hashlib.md5(query.encode()).hexdigest()] for query in queries]
    )
    on_update(f"Computing cosine similarity for {len(queries)} queries")
    cosine_scores = util.pytorch_cos_sim(embeddings_list, embeddings_list)

    for i in range(n):
        if visited[i]:
            continue
        visited[i] = True

        group = [
            {
                "index": i,
                "timestamp": datetime.datetime.fromisoformat(str(timestamps[i])),
                "query": queries[i],
                "similarity": 1.0,
            }
        ]
        filtered = []
        for j in range(i + 1, n):
            if visited[j]:
                continue

            max_sim = cosine_scores[i][j].item()
            if max_sim < grouping_threshold:
                continue

            ts = datetime.datetime.fromisoformat(str(timestamps[j]))
            min_time_diff = min([abs(entry["timestamp"] - ts) for entry in group])
            if (
                min_time_diff > datetime.timedelta(hours=12)
                and max_sim < filter_threshold
            ):
                continue

            entry = {
                "index": j,
                "timestamp": ts,
                "query": queries[j],
                "similarity": max_sim,
            }

            visited[j] = True
            if max_sim < filter_threshold:
                group.append(entry)
            else:
                filtered.append(entry)

        group = sorted(group, key=lambda entry: entry["timestamp"], reverse=True)
        groups.append(
            {
                "group": group,
                "filtered": filtered,
                "max_ts": group[0]["timestamp"],
            }
        )

    groups = sorted(groups, key=lambda group: group["max_ts"], reverse=True)
    return groups


def compute_dataset(on_update, force_reload):
    results = fetch_kusto_queries(on_update, force_reload)
    dataset = group_by_similarity(on_update, results)
    return dataset


from textual.app import App, ComposeResult
from textual.widgets import Footer, Header, OptionList
from textual.widgets.option_list import Option
from textual.containers import Container, VerticalScroll
from textual.screen import Screen
from textual import work
from textual.worker import Worker, get_current_worker
from textual.message import Message
from textual.widgets import LoadingIndicator
from textual.widgets import RichLog


import pyperclip


class LoadingScreen(Screen):
    BINDINGS = [
        ("escape", "quit", "Quit"),
        ("q", "quit", "Quit"),
    ]

    CSS = """
Screen {
    layout: grid;
    grid-size: 1;
    grid-columns: auto 1fr 1fr;
    grid-rows: 25% 75%;
}

.loading {
    height: 25%;
}

.log {
    height: 75%;
}
    """

    def __init__(self, force_reload, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self._force_reload = force_reload

    def compose(self) -> ComposeResult:
        yield Header()
        yield LoadingIndicator(classes="loading")
        yield RichLog(highlight=True, markup=False, classes="log")
        yield Footer()

    class RefreshLoadingMessage(Message):
        def __init__(self, text) -> None:
            self.text = text
            super().__init__()

    class RefreshQuery(Message):
        def __init__(self, queries) -> None:
            self.queries = queries
            super().__init__()

    def action_force_reload_data(self):
        self.reload_data(force_reload=True)

    @work(exclusive=True, thread=True)
    def reload_data(self, force_reload):
        def on_update(text):
            self.post_message(self.RefreshLoadingMessage(text))

        worker = get_current_worker()
        queries = compute_dataset(on_update, force_reload)
        if not worker.is_cancelled:
            self.post_message(self.RefreshQuery(queries))

    def on_mount(self) -> None:
        self.reload_data(force_reload=self._force_reload)

    def on_loading_screen_refresh_loading_message(self, message: RefreshLoadingMessage):
        text_log = self.query_one(RichLog)
        text_log.write(message.text)

    def on_loading_screen_refresh_query(self, message: RefreshQuery):
        self.dismiss(message.queries)


class ListScreen(Screen):

    BINDINGS = [
        ("escape", "quit", "Quit"),
        ("q", "quit", "Quit"),
        ("right", "go_to_group()", "Go to Group"),
        ("c", "copy_selected_query()", "Copy Selected Query"),
        ("r", "reload_data()", "Refresh"),
    ]

    def __init__(
        self,
        app,
    ):
        super().__init__()
        self._owner = app
        self._highlighted = None
        self._queries = []

    def compose(self) -> ComposeResult:
        yield Header()
        yield OptionList(id="query_group_list", markup=False)
        yield Footer()

    def on_option_list_option_highlighted(self, message: OptionList.OptionHighlighted):
        self._highlighted = message.option_index

    def on_option_list_option_selected(self, message: OptionList.OptionSelected):
        group = self._queries[message.option_index]

        if len(group["group"]) == 1:
            return

        self._owner.create_group_screen(group)

    def on_mount(self) -> None:
        self._owner.push_screen(LoadingScreen(False), self.refresh_queries)

    def action_reload_data(self) -> None:
        self._owner.push_screen(LoadingScreen(True), self.refresh_queries)

    def refresh_queries(self, queries) -> None:
        if queries is None:
            return

        self._queries = queries

        optlist: OptionList = self.query_one("#query_group_list")

        options = []
        for idx, group in enumerate(self._queries):
            options.append(
                Option(
                    f"(Timestamp: {group['max_ts']}, Size: {len(group['group'])}). Example: {group['group'][0]['query']}"
                )
            )

            # if idx < len(self._queries) - 1:
            #     options.append(None)

        optlist.clear_options()
        optlist.add_options(options)

    def action_go_to_group(self):
        if self._highlighted is None:
            return

        group = self._queries[self._highlighted]
        if len(group["group"]) == 1:
            return

        self._owner.create_group_screen(group)

    def action_copy_selected_query(self):
        if self._highlighted is None:
            return

        pyperclip.copy(self._queries[self._highlighted]["group"][0]["query"])


class GroupScreen(Screen):
    BINDINGS = [
        ("b", "back()", "Main Screen"),
        ("escape", "back()", "Main Screen"),
        ("left", "back()", "Main Screen"),
        ("q", "quit", "Quit"),
        ("c", "copy()", "Copy Selected Query"),
    ]

    def __init__(self, dataset):
        super().__init__()
        self._dataset = dataset
        self._highlighted = None

    def compose(self) -> ComposeResult:
        yield Header()

        options = []
        for idx, entry in enumerate(self._dataset["group"]):
            options.append(
                Option(
                    f"Timestamp: {entry['timestamp']}, Similarity: {entry['similarity']:.4f}, Query: {entry['query']}"
                )
            )

            # if idx < len(self._dataset["group"]) - 1:
            #     options.append(Separator())

        yield OptionList(*options, markup=False)

        yield Footer()

    def on_option_list_option_highlighted(self, message: OptionList.OptionHighlighted):
        self._highlighted = message.option_index

    def action_back(self):
        self.dismiss()

    def action_copy(self):
        pyperclip.copy(self._dataset["group"][self._highlighted]["query"])


# TODO: search on main screen
# TODO: send to kusto explorer
# TODO: multiple Kusto clusters
# TODO: add bindings for arrows into status
# TODO: embed the AST instead of the raw Kusto text
# TODO: group queries that are perfect prefixes of each other


class GroupSelectorApp(App):
    TITLE = "Walk Down Kusto Kusto Memory Lane"
    ENABLE_COMMAND_PALETTE = False

    def __init__(self):
        super().__init__()

    async def on_mount(self):
        self.push_screen(ListScreen(self))

    def create_group_screen(self, query_group):
        self.push_screen(GroupScreen(query_group))


def main():
    try:
        app = GroupSelectorApp()
        app.run()
    except Exception as e:
        print("An error occurred:", e)
        raise


if __name__ == "__main__":
    main()
