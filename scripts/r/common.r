# ---- Loading libraries ----
library_location <- "/Users/taivo/Library/R/3.2/library"
library.path <- cat(.libPaths())

library(dplyr, lib.loc=library_location)
library(ggplot2, lib.loc=library_location)
library(reshape2, lib.loc=library_location)
library(stringr, lib.loc=library_location)

# ---- Theme ----

asl_theme = theme_bw() +
  theme(panel.grid.minor=element_blank()) +
  theme(panel.grid.major=element_line(color="#888888"))
  theme(text=element_text(family="Open Sans"))

color_dark = "#322270"
color_medium = "#7963cf"
color_light = "#cdc4ed"

fig_width = 10
fig_height = 5