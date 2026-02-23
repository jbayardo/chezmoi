# /// script
# dependencies = ["pandas", "plotly", "jinja2", "click", "scipy"]
# ///

import os
import sys
import webbrowser

import click
import pandas as pd
import plotly.graph_objects as go
from jinja2 import Template
from plotly.subplots import make_subplots
from scipy.stats import beta

TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>{{ title }}</title>

    <style>
        .content {
            max-width: 1200px;
            margin: auto;
            padding: 20px;
        }

        h1 {
            text-align: center;
        }
    </style>
</head>

<body>
    <div class="content">
        <h1>{{ title }}</h1>

        {{ plots }}
    </div>
</body>
</html>
"""


# Function to calculate credible intervals for probabilities
def credible_interval(successes, trials, confidence=0.95):
    alpha = 1.0 - confidence
    lower = beta.ppf(alpha / 2, successes + 1, trials - successes + 1)
    upper = beta.ppf(1 - alpha / 2, successes + 1, trials - successes + 1)
    return lower, upper


@click.command()
@click.argument("csv_path", type=click.Path(exists=True), required=False, default=None)
@click.option(
    "--category_column", "-c", default="Category", help="Name of the category column"
)
@click.option("--count_column", "-n", default=None, help="Name of the count column")
def plot_histogram(csv_path, category_column, count_column):
    if csv_path is None:
        csv_path = sys.stdin
    df = pd.read_csv(csv_path)

    # Summarize data
    if count_column:
        df_summary = df.groupby(category_column)[count_column].sum().reset_index()
    else:
        df_summary = df[category_column].value_counts().reset_index()
        df_summary.columns = [category_column, "Count"]

    total_count = df_summary["Count"].sum()

    # Calculate probabilities and credible intervals
    df_summary["Probability"] = df_summary["Count"] / total_count
    df_summary["CI Lower"], df_summary["CI Upper"] = zip(
        *df_summary.apply(
            lambda row: credible_interval(row["Count"], total_count), axis=1
        )
    )

    # Create subplot
    fig = make_subplots(
        rows=2, cols=1, subplot_titles=("Counts", "Probability with Credible Intervals")
    )

    # Plot for unnormalized counts
    fig.add_trace(
        go.Bar(x=df_summary[category_column], y=df_summary["Count"], name="Counts"),
        row=1,
        col=1,
    )

    # Plot for probabilities and credible intervals
    fig.add_trace(
        go.Scatter(
            x=df_summary[category_column],
            y=df_summary["Probability"],
            name="Probability",
            mode="lines+markers",
            line=dict(color="red"),
        ),
        row=2,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=df_summary[category_column],
            y=df_summary["CI Lower"],
            mode="lines",
            line=dict(color="green"),
            name="95% CI Lower",
        ),
        row=2,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=df_summary[category_column],
            y=df_summary["CI Upper"],
            mode="lines",
            line=dict(color="green"),
            name="95% CI Upper",
            fill="tonexty",
        ),
        row=2,
        col=1,
    )

    fig.update_xaxes(tickangle=45)

    fig.update_layout(
        height=2048,
        showlegend=True,
        margin=dict(l=20, r=20, t=50, b=20),
    )

    # Render HTML
    template_arguments = {
        "title": "Histogram and Probability Estimates",
        "plots": fig.to_html(full_html=False),
    }
    file_path = os.path.abspath("plot_histogram.html")
    with open(file_path, "w", encoding="utf-8") as output_file:
        j2_template = Template(TEMPLATE)
        output_file.write(j2_template.render(template_arguments))

    webbrowser.open(file_path)


if __name__ == "__main__":
    plot_histogram()
