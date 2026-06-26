args <- commandArgs(trailingOnly = TRUE)
input_csv <- args[1]
output_png <- args[2]
fc_threshold <- as.numeric(args[3])
p_threshold <- as.numeric(args[4])

df <- read.csv(input_csv, stringsAsFactors = FALSE, check.names = FALSE)
df$neg_log10_p <- -log10(pmax(df[["_pvalue"]], 1e-300))
df$regulation <- "Not significant"
df$regulation[df[["_logfc"]] >= fc_threshold & df[["_pvalue"]] < p_threshold] <- "Upregulated"
df$regulation[df[["_logfc"]] <= -fc_threshold & df[["_pvalue"]] < p_threshold] <- "Downregulated"

datasets <- unique(df$dataset)
panel_count <- length(datasets)
cols <- 1
rows <- panel_count

label_candidates <- function(current, direction, limit = 16) {
  if (direction == "up") {
    candidates <- current[current$regulation == "Upregulated", ]
    candidates <- candidates[order(candidates[["_pvalue"]], -candidates[["_logfc"]]), ]
  } else {
    candidates <- current[current$regulation == "Downregulated", ]
    candidates <- candidates[order(candidates[["_pvalue"]], candidates[["_logfc"]]), ]
  }
  candidates <- candidates[!is.na(candidates$gene_label) & candidates$gene_label != "", ]
  head(candidates, limit)
}

make_label_layout <- function(points, side, y_gap) {
  if (nrow(points) == 0) {
    return(data.frame())
  }

  points <- points[order(points$neg_log10_p), ]
  label_y <- points$neg_log10_p
  if (length(label_y) > 1) {
    for (i in 2:length(label_y)) {
      if (label_y[i] - label_y[i - 1] < y_gap) {
        label_y[i] <- label_y[i - 1] + y_gap
      }
    }
  }

  lane <- rep(c(0, 1, 2), length.out = nrow(points))
  offset <- 0.48 + lane * 0.34
  label_x <- if (side == "right") points[["_logfc"]] + offset else points[["_logfc"]] - offset

  label_cex <- 0.76
  label_width <- strwidth(points$gene_label, cex = label_cex, font = 2)
  label_height <- strheight(points$gene_label, cex = label_cex, font = 2)
  label_pad_x <- max(strwidth("MM", cex = label_cex, font = 2), 0.05)
  label_pad_y <- max(strheight("M", cex = label_cex, font = 2) * 0.28, 0.03)

  data.frame(
    point_x = points[["_logfc"]],
    point_y = points$neg_log10_p,
    label_x = label_x,
    label_y = label_y,
    label = points$gene_label,
    box_left = label_x - ifelse(side == "left", label_width + label_pad_x, label_pad_x),
    box_right = label_x + ifelse(side == "left", label_pad_x, label_width + label_pad_x),
    box_bottom = label_y - label_height * 0.75 - label_pad_y,
    box_top = label_y + label_height * 0.75 + label_pad_y,
    stringsAsFactors = FALSE
  )
}

draw_labels <- function(layout, color, side) {
  if (nrow(layout) == 0) {
    return()
  }

  for (i in seq_len(nrow(layout))) {
    x <- layout$point_x[i]
    y <- layout$point_y[i]
    label <- layout$label[i]
    label_x <- layout$label_x[i]
    label_y <- layout$label_y[i]
    label_cex <- 0.76

    segments(x, y, label_x, label_y, col = color, lwd = 0.7)
    rect(
      layout$box_left[i],
      layout$box_bottom[i],
      layout$box_right[i],
      layout$box_top[i],
      border = color,
      col = adjustcolor("white", alpha.f = 0.78),
      lwd = 0.7,
      xpd = TRUE
    )
    text(
      label_x,
      label_y,
      labels = label,
      col = color,
      cex = label_cex,
      font = 2,
      pos = if (side == "right") 4 else 2,
      xpd = TRUE
    )
  }
}

label_positions <- function(layout) {
  if (nrow(layout) == 0) {
    return(data.frame(x = numeric(0), y = numeric(0)))
  }
  data.frame(
    x = c(layout$label_x, layout$box_left, layout$box_right),
    y = c(layout$label_y, layout$box_bottom, layout$box_top)
  )
}

png(output_png, width = 1300, height = max(720, rows * 720), res = 130)
par(mfrow = c(rows, cols), mar = c(5.2, 5.2, 3.8, 7.2), oma = c(0, 0, 2, 0))

for (dataset in datasets) {
  current <- df[df$dataset == dataset, ]
  down_labels <- label_candidates(current, "down")
  up_labels <- label_candidates(current, "up")
  point_color <- ifelse(
    current$regulation == "Upregulated",
    "#E23B3B",
    ifelse(current$regulation == "Downregulated", "#3758A8", "#111111")
  )
  x_values <- current[["_logfc"]]
  y_values <- current$neg_log10_p
  if (nrow(down_labels) > 0) {
    x_values <- c(x_values, down_labels[["_logfc"]] - 1.8)
    y_values <- c(y_values, down_labels$neg_log10_p + seq_len(nrow(down_labels)) * 0.45)
  }
  if (nrow(up_labels) > 0) {
    x_values <- c(x_values, up_labels[["_logfc"]] + 1.8)
    y_values <- c(y_values, up_labels$neg_log10_p + seq_len(nrow(up_labels)) * 0.45)
  }

  x_limits <- range(x_values, na.rm = TRUE)
  y_limits <- range(y_values, na.rm = TRUE)
  x_padding <- max(1, diff(x_limits) * 0.08)
  y_padding <- max(1, diff(y_limits) * 0.12)
  x_limits <- c(x_limits[1] - x_padding, x_limits[2] + x_padding)
  y_limits <- c(0, y_limits[2] + y_padding)

  plot(
    current[["_logfc"]],
    current$neg_log10_p,
    pch = 16,
    cex = ifelse(current$regulation == "Not significant", 0.42, 0.58),
    col = point_color,
    xlab = "Log 2 Fold-Change",
    ylab = "-log10(P.Value)",
    main = dataset,
    xlim = x_limits,
    ylim = y_limits,
    frame.plot = FALSE
  )
  grid(col = "#FFFFFF", lwd = 1)
  abline(v = c(-fc_threshold, fc_threshold), col = "#8372D8", lty = 1, lwd = 1.4)
  abline(h = -log10(p_threshold), col = "#8372D8", lty = 2, lwd = 1.4)

  raw_y_limits <- range(current$neg_log10_p, na.rm = TRUE)
  y_gap <- max(0.35, diff(raw_y_limits) * 0.035)
  down_layout <- make_label_layout(down_labels, "left", y_gap)
  up_layout <- make_label_layout(up_labels, "right", y_gap)
  draw_labels(down_layout, "#3758A8", "left")
  draw_labels(up_layout, "#E23B3B", "right")

  legend(
    "right",
    inset = c(-0.12, 0),
    legend = c("Not Significant", "Significantly Down Regulated", "Significantly Up Regulated"),
    col = c("#111111", "#3758A8", "#E23B3B"),
    pch = 16,
    bty = "n",
    cex = 0.75,
    title = "Significance",
    xpd = TRUE
  )
}

mtext("Volcano Plot from Uploaded Differential Expression Sheets", outer = TRUE, cex = 1.2, font = 2)
dev.off()
