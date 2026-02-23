# /// script
# dependencies = ["pandas", "plotly", "jinja2", "click"]
# ///

import os
import sys
import pandas as pd
import plotly.graph_objects as go
import webbrowser
from plotly.subplots import make_subplots
from jinja2 import Template
import click


TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>{{ title }}</title>

    <style>
        .stats-table, .stats-table th, .stats-table td {
            border: 1px solid black;
            border-collapse: collapse;
            vertical-align: center;
            text-align: center;
            align-items: center;
            padding: 8px;
        }

        table.stats-table {
            margin: 20px auto;

        }

        .stats-table th {
            background-color: #f2f2f2;
        }

        .content {
            max-width: 1200px;
            margin: auto;
            padding: 20px;
        }

        h1 {
            text-align: center;
        }
    </style>

    <script>
    document.addEventListener('DOMContentLoaded', function() {
        var cells = document.querySelectorAll('.stats-table td');

        cells.forEach(function(cell) {
            var num = parseFloat(cell.innerText.replace(/,/g, ''));
            if (!isNaN(num)) {
                cell.style.whiteSpace = 'nowrap';
                cell.innerHTML = num.toLocaleString('en-US', {minimumFractionDigits: 1, maximumFractionDigits: 1}).replace(/,/g, ' ');
            }
        });
    });

    document.addEventListener('copy', function(e) {
        var selection = document.getSelection();
        if (selection.rangeCount > 0) {
            var text = selection.toString();
            // Remove spaces and replace European style decimals if necessary
            var modifiedText = text.replace(/ /g, ''); // Remove spaces for thousand separators
            e.clipboardData.setData('text/plain', modifiedText);
            e.preventDefault(); // Prevent the default copy behavior
        }
    });
    </script>
</head>

<body>
    <div class="content">
        <h1>{{ title }}</h1>

        <table class="stats-table">
        {{ table }}
        </table>

        {{ plots }}
    </div>
</body>
</html>
"""


# TODO: add flags for each detection rule
# TODO: add more flags for customization
# TODO: don't count measurements that are spaced out for the central lines, or runs rule
# TODO: nicer template?
@click.command()
@click.argument(
    "csv_path", type=click.Path(exists=True), required=False, default=sys.stdin
)
@click.option(
    "--connected",
    is_flag=True,
    help="Connect the data points with lines instead of using a scatterplot",
)
@click.option(
    "--median",
    is_flag=True,
    help="Use median instead of mean for central line calculation",
)
@click.option(
    "--ewma",
    default=None,
    type=click.INT,
    help="Use an Exponentially Weighted Moving Average with the specified span for central line calculation",
)
@click.option(
    "--median-mr",
    is_flag=True,
    help="Use median instead of mean for central line calculation of the Moving Range",
)
@click.option(
    "--ewma-mr",
    default=None,
    type=click.INT,
    help="Use an Exponentially Weighted Moving Average with the specified span for central line calculation of the Moving Range",
)
@click.option(
    "--x",
    "x_column",
    default="Timestamp",
    help="Name of the column to use for the X-axis",
)
@click.option(
    "--y", "y_column", default="Value", help="Name of the column to use for the Y-axis"
)
def plot_xmr_chart(
    csv_path=sys.stdin,
    connected: bool = False,
    median: bool = False,
    ewma: int = None,
    median_mr: bool = False,
    ewma_mr: int = None,
    x_column: str = "Timestamp",
    y_column: str = "Value",
):
    df = pd.read_csv(csv_path)
    if pd.api.types.is_datetime64_any_dtype(df[x_column]):
        df[x_column] = pd.to_datetime(df[x_column])
    else:
        pass

    df.sort_values(by=x_column, inplace=True)
    df["Moving Range"] = df[y_column].diff().abs()

    avg_X = df[y_column].mean()
    if median:
        central_X = pd.Series([df[y_column].median()] * len(df))
        factor_X = 3.14
    elif ewma is not None:
        central_X = df[y_column].ewm(span=ewma).mean()
        factor_X = 2.66
    else:
        central_X = pd.Series([avg_X] * len(df))
        factor_X = 2.66

    avg_MR = df["Moving Range"].mean()
    if median_mr:
        central_MR = pd.Series([df["Moving Range"].median()] * len(df))
        factor_MR = 3.86
    elif ewma_mr is not None:
        central_MR = df["Moving Range"].ewm(span=ewma_mr).mean()
        factor_MR = 3.27
    else:
        central_MR = pd.Series([avg_MR] * len(df))
        factor_MR = 3.27

    UCL_X = central_X + factor_X * central_MR
    LCL_X = central_X - factor_X * central_MR
    UCL_MR = factor_MR * central_MR

    # TODO: when charting, the order of the data should be preserved, as in, Anomaly should trump other highlights, for example
    # Detection Rule One: Highlight points outside the control limits
    df["Outside Limits"] = (df[y_column] > UCL_X) | (df[y_column] < LCL_X)

    # Detection Rule Two: Highlight runs of eight successive points above or below the central line
    df["Above Central Line"] = df[y_column] > central_X
    df["Below Central Line"] = df[y_column] < central_X

    def mark_runs(df, column, window_size):
        # Identify where runs start
        df["Run Start"] = df[column] & (~df[column].shift(1, fill_value=False))
        # Identify all positions part of a run
        df["Run Index"] = df["Run Start"].cumsum()
        # Count occurrences within each run
        run_counts = df.groupby("Run Index")[column].transform("sum")
        return run_counts >= window_size

    df["Highlight Above"] = mark_runs(df, "Above Central Line", 8)
    df["Highlight Below"] = mark_runs(df, "Below Central Line", 8)

    # Detection Rule Three: Highlight three out of four consecutive points near the limits
    upper_quarter = central_X + 0.5 * (UCL_X - central_X)
    lower_quarter = central_X - 0.5 * (central_X - LCL_X)

    # Calculate points near the upper or lower quarter limits
    df["Near Upper Limit"] = df[y_column] > upper_quarter
    df["Near Lower Limit"] = df[y_column] < lower_quarter

    # Detect windows where at least three out of four consecutive points are near the upper limit
    df["Temp Highlight Upper Limits"] = (
        (df["Near Upper Limit"].rolling(window=4).sum() >= 3).astype(bool).fillna(False)
    )

    # Detect windows where at least three out of four consecutive points are near the lower limit
    df["Temp Highlight Lower Limits"] = (
        (df["Near Lower Limit"].rolling(window=4).sum() >= 3).astype(bool).fillna(False)
    )

    # Highlight all four points in any window where the upper limit condition is met using backward fill
    df["Highlight Near Upper Limits"] = (
        df["Temp Highlight Upper Limits"]
        .replace({False: None})
        .bfill(limit=3)
        .astype(bool)
        .fillna(False)
    )

    # Highlight all four points in any window where the lower limit condition is met using backward fill
    df["Highlight Near Lower Limits"] = (
        df["Temp Highlight Lower Limits"]
        .replace({False: None})
        .bfill(limit=3)
        .astype(bool)
        .fillna(False)
    )

    # Combine the two highlighting conditions into a single column
    df["Highlight Near Limits"] = (
        df["Highlight Near Upper Limits"] | df["Highlight Near Lower Limits"]
    )

    # Filter data for plotting
    outside_limits = df[df["Outside Limits"]]
    highlight_above = df[df["Highlight Above"]]
    highlight_below = df[df["Highlight Below"]]
    highlight_near_limits = df[df["Highlight Near Limits"]]

    # Create subplots
    fig = make_subplots(
        rows=2,
        cols=2,
        subplot_titles=(
            "X Chart",
            "X Histogram",
            "Moving Range Chart",
            "Moving Range Histogram",
        ),
        specs=[[{"type": "xy"}, {"type": "xy"}], [{"type": "xy"}, {"type": "xy"}]],
        column_widths=[0.80, 0.20],
    )

    # Add traces to X chart
    fig.add_trace(
        go.Scatter(
            x=df[x_column],
            y=df[y_column],
            mode="lines+markers" if connected else "markers",
            name=y_column,
        ),
        row=1,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=highlight_above[x_column],
            y=highlight_above[y_column],
            mode="markers",
            marker=dict(color="orange"),
            name="Run Above Central",
        ),
        row=1,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=highlight_below[x_column],
            y=highlight_below[y_column],
            mode="markers",
            marker=dict(color="orange"),
            name="Run Below Central",
        ),
        row=1,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=highlight_near_limits[x_column],
            y=highlight_near_limits[y_column],
            mode="markers",
            marker=dict(color="magenta"),
            name="Near Limits",
        ),
        row=1,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=outside_limits[x_column],
            y=outside_limits[y_column],
            mode="markers",
            marker=dict(color="red"),
            name="Anomaly",
        ),
        row=1,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=df[x_column],
            y=central_X,
            line_dash="dash",
            line_color="green",
            name="Central Line X",
            mode="lines",
        ),
        row=1,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=df[x_column],
            y=UCL_X,
            line_dash="dash",
            line_color="red",
            name="UCL",
            mode="lines",
        ),
        row=1,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=df[x_column],
            y=LCL_X,
            line_dash="dash",
            line_color="red",
            name="LCL",
            mode="lines",
        ),
        row=1,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=df[x_column],
            y=upper_quarter,
            line_dash="dot",
            line_color="orange",
            mode="lines",
            name="Upper Quarter",
        ),
        row=1,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=df[x_column],
            y=lower_quarter,
            line_dash="dot",
            line_color="orange",
            mode="lines",
            name="Lower Quarter",
        ),
        row=1,
        col=1,
    )

    # Add MR chart
    fig.add_trace(
        go.Scatter(
            x=df[x_column],
            y=df["Moving Range"],
            mode="lines+markers" if connected else "markers",
            name="Moving Range",
        ),
        row=2,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=df[x_column],
            y=central_MR,
            line_dash="dash",
            line_color="green",
            name="Central Line MR",
            mode="lines",
        ),
        row=2,
        col=1,
    )
    fig.add_trace(
        go.Scatter(
            x=df[x_column],
            y=UCL_MR,
            line_dash="dash",
            line_color="red",
            name="UCL MR",
            mode="lines",
        ),
        row=2,
        col=1,
    )

    # Add histograms
    fig.add_trace(
        go.Histogram(
            y=df[y_column],
            xaxis="x2",
            name="Histogram Value",
            orientation="h",
            marker=dict(color="blue"),
        ),
        row=1,
        col=2,
    )
    fig.add_trace(
        go.Histogram(
            y=df["Moving Range"],
            xaxis="x4",
            name="Histogram Moving Range",
            orientation="h",
            marker=dict(color="blue"),
        ),
        row=2,
        col=2,
    )

    fig.update_xaxes(tickangle=45)

    fig.update_layout(
        height=800,
        showlegend=True,
        xaxis2=dict(domain=[0.8, 1], title="Count"),
        xaxis4=dict(domain=[0.8, 1], title="Count"),
    )

    percentiles = [0.25, 0.5, 0.75, 0.90, 0.95, 0.99, 0.999]
    X_desc = pd.DataFrame(df[y_column].describe(percentiles=percentiles)).T
    MR_desc = pd.DataFrame(df["Moving Range"].describe(percentiles=percentiles)).T

    desc = pd.concat([X_desc, MR_desc]).to_html(border=0, classes="stats-table")

    template_arguments = {
        "title": "XmR Chart for {}".format(y_column),
        "table": desc,
        "plots": fig.to_html(full_html=False),
    }
    file_path = os.path.abspath("plot_xmr_chart.html")
    with open(file_path, "w", encoding="utf-8") as output_file:
        j2_template = Template(TEMPLATE)
        output_file.write(j2_template.render(template_arguments))

    webbrowser.open(file_path)


if __name__ == "__main__":
    plot_xmr_chart()
