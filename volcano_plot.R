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
cols <- min(panel_count, 3)
rows <- ceiling(panel_count / cols)

label_candidates <- function(current, direction, limit = 20) {
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

draw_labels <- function(points, color, side) {
  if (nrow(points) == 0) {
    return()
  }

  for (i in seq_len(nrow(points))) {
    x <- points[["_logfc"]][i]
    y <- points$neg_log10_p[i]
    label <- points$gene_label[i]
    offset <- 0.34 + (i %% 4) * 0.07
    label_x <- if (side == "right") x + offset else x - offset
    label_y <- y + 0.12 + (i %% 5) * 0.08
    align <- if (side == "right") 0 else 1
    label_width <- strwidth(label, cex = 0.58)
    label_height <- strheight(label, cex = 0.58)

    segments(x, y, label_x, label_y, col = color, lwd = 0.7)
    rect(
      label_x - if (align == 1) label_width else 0,
      label_y - label_height * 0.7,
      label_x + if (align == 1) 0 else label_width,
      label_y + label_height * 0.7,
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
      cex = 0.58,
      pos = if (side == "right") 4 else 2,
      xpd = TRUE
    )
  }
}

png(output_png, width = 1500, height = max(760, rows * 620), res = 130)
par(mfrow = c(rows, cols), mar = c(5.1, 5.1, 3.5, 8.8), oma = c(0, 0, 2, 0))

for (dataset in datasets) {
  current <- df[df$dataset == dataset, ]
  point_color <- ifelse(
    current$regulation == "Upregulated",
    "#E23B3B",
    ifelse(current$regulation == "Downregulated", "#3758A8", "#111111")
  )

  plot(
    current[["_logfc"]],
    current$neg_log10_p,
    pch = 16,
    cex = ifelse(current$regulation == "Not significant", 0.42, 0.58),
    col = point_color,
    xlab = "Log 2 Fold-Change",
    ylab = "-log10(P.Value)",
    main = dataset,
    frame.plot = FALSE
  )
  grid(col = "#FFFFFF", lwd = 1)
  abline(v = c(-fc_threshold, fc_threshold), col = "#8372D8", lty = 1, lwd = 1.4)
  abline(h = -log10(p_threshold), col = "#8372D8", lty = 2, lwd = 1.4)

  down_labels <- label_candidates(current, "down")
  up_labels <- label_candidates(current, "up")
  draw_labels(down_labels, "#3758A8", "left")
  draw_labels(up_labels, "#E23B3B", "right")

  if (dataset == tail(datasets, 1)) {
    legend(
      "right",
      inset = c(-0.30, 0),
      legend = c("Not Significant", "Significantly Down Regulated", "Significantly Up Regulated"),
      col = c("#111111", "#3758A8", "#E23B3B"),
      pch = 16,
      bty = "n",
      cex = 0.75,
      title = "Significance",
      xpd = TRUE
    )
  }
}

mtext("Volcano Plot from Uploaded Differential Expression Sheets", outer = TRUE, cex = 1.2, font = 2)
dev.off()
