args <- commandArgs(trailingOnly = TRUE)
input_csv <- args[1]
output_png <- args[2]
fc_threshold <- as.numeric(args[3])
p_threshold <- as.numeric(args[4])

df <- read.csv(input_csv, stringsAsFactors = FALSE, check.names = FALSE)
df$neg_log10_p <- -log10(pmax(df[["_pvalue"]], 1e-300))
df$significant <- abs(df[["_logfc"]]) >= fc_threshold & df[["_pvalue"]] < p_threshold

datasets <- unique(df$dataset)
panel_count <- length(datasets)
cols <- min(panel_count, 3)
rows <- ceiling(panel_count / cols)

png(output_png, width = 1300, height = max(650, rows * 520), res = 130)
par(mfrow = c(rows, cols), mar = c(4.5, 4.7, 3.2, 1.2), oma = c(0, 0, 2, 0))

for (dataset in datasets) {
  current <- df[df$dataset == dataset, ]
  is_common <- tolower(as.character(current$is_common)) == "true"
  point_color <- ifelse(is_common, "#E35D48",
                 ifelse(current$significant, "#2D7DD2", "#B8C0CC"))
  plot(
    current[["_logfc"]],
    current$neg_log10_p,
    pch = 16,
    cex = 0.55,
    col = point_color,
    xlab = "logFC",
    ylab = "-log10(p value)",
    main = dataset,
    frame.plot = FALSE
  )
  abline(v = c(-fc_threshold, fc_threshold), col = "#5C6675", lty = 2, lwd = 1)
  abline(h = -log10(p_threshold), col = "#5C6675", lty = 2, lwd = 1)
  legend(
    "topright",
    legend = c("Common filtered genes", "Passes filter", "Other genes"),
    col = c("#E35D48", "#2D7DD2", "#B8C0CC"),
    pch = 16,
    bty = "n",
    cex = 0.8
  )
}

mtext("Volcano Plot from Uploaded Differential Expression Sheets", outer = TRUE, cex = 1.25, font = 2)
dev.off()
