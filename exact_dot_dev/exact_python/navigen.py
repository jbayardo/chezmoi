# /// script
# dependencies = ["litellm", "diskcache", "pydantic"]
# ///
import argparse
import logging
import os
import shutil
import subprocess
import hashlib
from typing import Any, Optional

import litellm
from litellm.caching.caching import Cache
from pydantic import BaseModel, Field
from diskcache import Cache as DiskCache


class MemoryCache(object):
    """
    A simple in-memory cache implementation.
    """

    def __init__(self):
        self.store = {}

    def get(self, key: str) -> Any:
        """
        Retrieve the value associated with the given key from the store.

        Args:
          key: The key whose associated value is to be returned.

        Returns:
          The value associated with the specified key, or None if the key is not found.
        """

        return self.store.get(key)

    def set(self, key: str, value: Any) -> None:
        """
        Sets the value for a given key in the store.

        Args:
          key: The key for which the value needs to be set.
          value: The value to be set for the given key.
        """

        self.store[key] = value


def fetch_help(exe_path):
    """
    Attempt to fetch help text from an executable by running it with
    common help flags. Returns the help text (str).
    """
    help_flags = ["--help", "-h", "/?"]
    help_text = ""
    errors = []

    for flag in help_flags:
        try:
            logging.debug("Running '%s %s'", exe_path, flag)
            process = subprocess.run(
                [exe_path, flag],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=5,
                check=True,
            )

            output = process.stdout.strip() or process.stderr.strip()
            if output:
                help_text = output
                break
        except subprocess.TimeoutExpired:
            logging.debug("Timeout running '%s %s'", exe_path, flag)
            errors.append(f"Timeout running {exe_path} {flag}")
        except Exception as e:
            logging.debug("Error running '%s %s': %s", exe_path, flag, e)
            errors.append(f"Error running {exe_path} {flag}: {e}")

    if not help_text:
        error_msg = "\n".join(errors) if errors else "No help text found"
        raise ValueError(f"Could not fetch help for {exe_path}: {error_msg}")

    logging.debug("Generated help text for: %s", exe_path)
    return help_text


class CheatsheetVariable(BaseModel):
    """
    The LLM will propose variables for each suggestion (if any).
    e.g.:
      {
        "name": "branch",
        "completion_command": "git branch | awk '{print $NF}'"
      }
    """

    variable: str = Field(
        ..., description="Name of the variable without angle brackets."
    )

    description: Optional[str] = Field(
        ..., description="Short description of the variable."
    )

    completion: Optional[str] = Field(
        ...,
        description=(
            r"Command that, when run, outputs possible completions one per line. "
            r"For example, for `git checkout <branch>`: `git branch | awk '{print $NF}'`. "
            r"It's not required to have a completion command for every variable. "
            r"Only include it if you are 100% sure it's useful to have the completion. "
            r"NEVER use `echo` or `printf` with a default value as a completion "
            r"(e.g. `echo 'Enter search pattern'`) "
        ),
    )


class CheatsheetSuggestion(BaseModel):
    """
    A single usage suggestion for the program, including a snippet of arguments,
    a short description, and an optional list of variables for which completions are possible.
    """

    description: str = Field(
        ..., description="Short explanation of what this example does."
    )

    arguments: str = Field(
        ...,
        description=(
            r"Command line snippet with angle bracket variables "
            r"(e.g. 'git checkout <branch>')."
            r"No command should ever have a variable with non-angle brackets "
            r"(e.g. 'git checkout [branch]', 'git checkout {branch}', etc.)."
        ),
    )

    variables: list[CheatsheetVariable] = Field(
        ...,
        description="List of variable definitions for the arguments, if any.",
    )


class ProgramInfo(BaseModel):
    """
    Input model: what info we send to the LLM about each discovered program.
    """

    program: str = Field(description="Name of the program.")
    exe_path: str = Field(description="Absolute path to the executable.")
    help_text: str = Field(description="Full help text for the executable.")


class ProgramSummary(BaseModel):
    """
    Output model (from LLM): summarized info about a program plus usage suggestions.
    """

    program: str = Field(description="Name of the program.")
    summary: str = Field(description="Short summary or overview of the program.")
    suggestions: list[CheatsheetSuggestion] = Field(
        description=(
            r"List of suggested invocations of the program. "
            r"There might be up to 10 suggested commands for this program. "
            r"Suggestions should never be for trivial commands "
            r"(e.g. the program name itself, running help, or getting the version). "
            r"Suggestions only be for uncommon useful commands. "
            r"Suggestions may never be for setup, installation, or single-use commands (e.g. init, or install). "
            r"Suggestions may be empty if there aren't any useful suggestions. "
        )
    )

    tags: list[str] = Field(
        description=(
            r"List of tags characterizing what the program does. Tags should be: "
            r"unique, "
            r"lowercase and contain no spaces, "
            r"relevant to the program's functionality, "
            r"useful for searching and filtering, "
            r"short and descriptive. "
        )
    )


class ProgramSummaryRequest(BaseModel):
    """
    Model that represents a request for a summary of programs.
    """

    programs: list[ProgramInfo] = Field(
        description="List of ProgramInfo objects, each describing a program's help text."
    )


class ProgramSummaryResponse(BaseModel):
    """
    Model representing a response containing a list of ProgramSummary objects.
    """

    programs: list[ProgramSummary] = Field(
        description="List of ProgramSummary objects produced by the LLM."
    )


def generate_summaries(request: ProgramSummaryRequest, model) -> ProgramSummaryResponse:
    """
    Send a JSON request to the LLM.
    The LLM must respond with ProgramSummaryResponse JSON that matches our schema.
    """

    # This message instructs the LLM to strictly produce JSON, using our schema.
    request_messages = [
        {
            "role": "system",
            "content": (
                "You are a helpful assistant designed to output JSON only.\n"
                "We have a custom schema: ProgramSummaryResponse. "
                "Do NOT include extra keys in the JSON. "
                "Do NOT include any markdown. "
                "Output must be valid JSON that can be parsed with the schema. "
                "For each program, provide a short summary plus a few usage suggestions. "
                "Each usage suggestion has 'description', 'arguments', and a 'variables' list.\n"
                "If the snippet has no variables, return an empty list for 'variables'.\n"
            ),
        },
        {
            "role": "user",
            "content": (
                "Below is a JSON with the programs to summarize. "
                "Your response must match this JSON schema EXACTLY:\n\n"
                f"{ProgramSummaryResponse.model_json_schema()}\n\n"
                "Here is the input:\n"
                f"{request.model_dump_json()}\n\n"
            ),
        },
    ]

    response = litellm.completion(
        model=model,
        response_format=ProgramSummaryResponse,
        messages=request_messages,
        max_tokens=16_000,
        temperature=0.2,
        caching=True,
    )

    returned_json = response["choices"][0]["message"]["content"].strip()
    logging.debug("LLM response: %s", returned_json)
    if not returned_json:
        raise ValueError("Empty response from LLM")

    try:
        results = ProgramSummaryResponse.model_validate_json(returned_json)
        return results
    except Exception as e:
        raise ValueError(f"Failed to parse LLM response: {returned_json}") from e


def batch_generate_summaries(
    uncached_programs: list[ProgramInfo], model: str, cache
) -> list[ProgramSummary]:
    """
    Generate summaries for uncached programs in small batches to avoid single large calls.
    Store results in the cache.
    """
    new_summaries = []
    if uncached_programs:
        batch_size = 10
        for i in range(0, len(uncached_programs), batch_size):
            batch = uncached_programs[i : i + batch_size]
            logging.debug(
                "Generating summaries for batch: %s", [p.exe_path for p in batch]
            )
            request = ProgramSummaryRequest(programs=batch)
            batch_results = generate_summaries(request, model)
            for j, summary in enumerate(batch_results.programs):
                prog = batch[j]
                sum_cache_key = f"summary:{prog.exe_path}:{model}"
                cache.set(sum_cache_key, summary)
                logging.debug("Cached summary for: %s", prog.exe_path)
                new_summaries.append(summary)
    return new_summaries


def fetch_summaries(exe_paths: list[str], model: str, cache) -> list[ProgramSummary]:
    """
    For each executable path:
      1) resolve it to a full path
      2) check if we have a cached ProgramSummary
      3) if not, gather help text, then pass to LLM
    Returns a list of ProgramSummary objects (cached + newly generated).
    """

    cached = []
    pending = []

    logging.debug(
        "Resolving executable paths and checking caches for help texts and summaries..."
    )
    for program in exe_paths:
        # Resolve/normalize
        raw_exe_path = program if os.path.isfile(program) else shutil.which(program)
        if not raw_exe_path:
            logging.error("Executable not found: %s", program)
            continue
        exe_path = os.path.normpath(os.path.abspath(raw_exe_path))

        # Try summary cache
        summary_cache_key = f"summary:{exe_path}:{model}"
        cached_summary = cache.get(summary_cache_key)
        if cached_summary:
            logging.debug("Summary cache hit for: %s", exe_path)
            cached.append(cached_summary)
            continue

        # Otherwise, gather help text
        help_cache_key = f"help_text:{exe_path}"
        help_text = cache.get(help_cache_key)
        if not help_text:
            try:
                logging.debug(
                    "No help text cache for: %s. Fetching help text...", exe_path
                )
                help_text = fetch_help(exe_path)
                cache.set(help_cache_key, help_text)
                logging.debug("Cached help text for: %s", exe_path)
            except Exception as e:
                logging.error("Failed to fetch help for %s: %s", exe_path, e)
                continue

        pending.append(
            ProgramInfo(program=program, exe_path=exe_path, help_text=help_text)
        )

    if not (cached or pending):
        raise SystemError("No valid programs found")

    generated = batch_generate_summaries(pending, model, cache)
    all_summaries = cached + generated
    all_summaries.sort(key=lambda s: s.program.lower())
    logging.debug("Total summaries obtained: %d", len(all_summaries))
    return all_summaries


def generate_cheatsheet(summaries: list[ProgramSummary]) -> str:
    """
    Convert the ProgramSummary objects into a single .cheat file, navi-compatible.
    """

    lines = []
    for summary in summaries:
        tags = [summary.program.lower()]
        for tag in summary.tags:
            tag = (
                tag.strip()
                .lower()
                .replace(" ", "_")
                .replace("-", "_")
                .replace(":", "_")
            )

            if tag and tag not in tags:
                tags.append(tag)

        if "autogen" not in tags:
            tags.append("autogen")

        lines.append(f"% {', '.join(tags)}")

        summary_txt = summary.summary.strip()
        if summary_txt:
            lines.append(f"# {summary_txt}")
            lines.append(summary.program)

        for suggestion in summary.suggestions:
            description = suggestion.description.strip()
            command_line = suggestion.arguments.strip()

            # Don't produce cheatsheet entries for help or version commands
            skip = False
            for flag in ["--help", "--version", "-h", "/?"]:
                if flag in command_line:
                    skip = True
                    break

            if skip:
                logging.debug("Skipping help/version command: %s", command_line)
                continue

            if not description or not command_line:
                logging.debug("Incomplete suggestion: %s", suggestion)
                continue

            lines.append(f"# {description}")
            lines.append(command_line)

            for variable in suggestion.variables:
                var_name = variable.variable
                completion_cmd = variable.completion
                if not var_name or not completion_cmd:
                    continue

                # Remove angle brackets and other delimiters
                if var_name.startswith("<") and var_name.endswith(">"):
                    var_name = var_name[1:-1]
                if var_name.startswith("[") and var_name.endswith("]"):
                    var_name = var_name[1:-1]
                if var_name.startswith("{") and var_name.endswith("}"):
                    var_name = var_name[1:-1]
                if var_name.startswith("$") and var_name.endswith("$"):
                    var_name = var_name[1:-1]
                if var_name.startswith("`") and var_name.endswith("`"):
                    var_name = var_name[1:-1]
                if var_name.startswith('"') and var_name.endswith('"'):
                    var_name = var_name[1:-1]
                if var_name.startswith("'") and var_name.endswith("'"):
                    var_name = var_name[1:-1]

                # Remove any leading/trailing whitespace
                var_name = var_name.strip()
                completion_cmd = completion_cmd.strip()

                # Ensure the variable name is part of the command
                if var_name not in command_line:
                    logging.debug(
                        "Variable '%s' not found in command line: %s",
                        var_name,
                        command_line,
                    )
                    continue

                # Add the variable completion command to the cheatsheet
                # This is a navi-specific format
                lines.append(f"$ {var_name}: {completion_cmd}")

        # Blank line separating each program
        lines.append("")

    return "\n".join(lines).strip()


def parse_arguments() -> argparse.Namespace:
    """
    Parses command-line arguments for the script.

    Returns:
      argparse.Namespace: Parsed command-line arguments.
    """

    parser = argparse.ArgumentParser(
        description="Summarize help text from executables and produce a navi-compatible cheatsheet (with LLM-provided variable completions)."
    )
    parser.add_argument(
        "--model", required=True, help="Model name for ChatGPT (or other LLM) calls."
    )
    parser.add_argument(
        "--verbose", action="store_true", help="Enable verbose logging."
    )
    parser.add_argument(
        "--in_memory_cache",
        action="store_true",
        help="Use an in-memory cache (instead of disk).",
    )
    parser.add_argument("executables", nargs="+", help="Executable names or paths.")
    return parser.parse_args()


def setup_logging(verbose: bool):
    """
    Configures the logging settings for the application.

    Args:0
      verbose: If True, sets the logging level to DEBUG. Otherwise, sets it to ERROR.
    """
    log_level = logging.DEBUG if verbose else logging.ERROR
    logging.basicConfig(level=log_level, format="%(levelname)s: %(message)s")
    logging.getLogger("LiteLLM").setLevel(logging.ERROR)
    litellm.log_raw_request_response = False


def sha256sum(file_path: str) -> str:
    """
    Calculate the SHA-256 checksum of a file.

    Args:
        filename (str): The path to the file for which the SHA-256 checksum is to be calculated.

    Returns:
        str: The SHA-256 checksum of the file in hexadecimal format.
    """
    if not os.path.isfile(file_path):
        raise FileNotFoundError(f"File not found: {file_path}")

    with open(file_path, "rb", buffering=0) as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def main():
    """
    Main function to execute the script.
    """

    args = parse_arguments()
    setup_logging(args.verbose)

    litellm.cache = Cache(type="disk")

    # Cache name is the hash of this script using hashlib
    script_path = os.path.abspath(__file__)
    cache_name = sha256sum(script_path)
    logging.debug("Cache name: %s", cache_name)

    with MemoryCache() if args.in_memory_cache else DiskCache(cache_name) as cache:
        summaries = fetch_summaries(args.executables, args.model, cache)

        cheatsheet_text = generate_cheatsheet(summaries)
        print(cheatsheet_text)


if __name__ == "__main__":
    main()
