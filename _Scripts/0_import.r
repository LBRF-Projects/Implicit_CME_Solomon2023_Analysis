###################################
### Tracelab data import script ###
###################################


### Import required packages ###

library(readr)
library(purrr)
library(tibble)
library(dplyr)
library(tidyr)
library(stringr)
library(forcats)

# Go back to the legacy readr backend

if (packageVersion("readr") >= "2.0.0") {
  options("readr.edition" = 1)
}


### Import task data ###

# Get file list

taskfiles <- list.files(
  "./_Data/task/", pattern = "*.txt",
  full.names = TRUE
)
is_error <- str_detect(basename(taskfiles), "incomplete")
erroneousfiles <- taskfiles[is_error]
taskfiles <- taskfiles[!is_error]

# Import trial-by-trial task data

col_overrides <- cols(
  sex = col_factor(levels = c("m", "f")),
  handedness = col_factor(levels = c("l", "r", "a")),
  random_seed = col_skip()
)

taskdat <- map_df(taskfiles, function(f) {
  id_num <- as.numeric(gsub("^p(\\d+).*", "\\1", basename(f)))
  df <- read_tsv(f, comment = "#", col_types = col_overrides, progress = FALSE)
  if (nrow(df) > 0) {
    df <- add_column(df, db_id = id_num, .before = 2)
    df
  }
})

### Import figure and tracing data ###

# Get file list

figfiles <- list.files(
  "./_Data/figure/", pattern = "*.zip",
  full.names = TRUE, recursive = TRUE
)


# Set aside any "learned" figures in a separate file list

is_learned <- str_detect(basename(figfiles), "learned")
learnedfiles <- figfiles[is_learned]
figfiles <- figfiles[!is_learned]


# Import all figure and response data into a single data frame (slow)

figdat <- map_df(figfiles, function(f) {
  tibble(
    fname = gsub("\\.zip", "", basename(f)),
    points = read_lines(I(unz(f, paste0(fname, ".tlfp"))), progress = FALSE),
    segments = read_lines(I(unz(f, paste0(fname, ".tlfs"))), progress = FALSE),
    frames = read_lines(I(unz(f, paste0(fname, ".tlf"))), progress = FALSE),
    tracing = read_lines(I(unz(f, paste0(fname, ".tlt"))), progress = FALSE)
  )
})


# Get id, session, block, trial, and date info from file names

cols_from_name <- c("id", "session", "block", "trial", "date")

figdat <- figdat %>%
  mutate(fname = gsub("[a-z\\.]", "", fname)) %>%
  separate(fname, cols_from_name, sep = "_", convert = TRUE) %>%
  arrange(id, session, block, trial)


# Extract and parse figure vertex point data

# NOTE: How this works: we select only the id/session/block/trial and unparsed
# points string columns from figdat, we strip the outer brackets from the points
# string, we split the points string for each trial into one row for each unique
# point by splitting on "), ", and then finally we split that column of "x, y"
# coordinates into two separate x and y columns.

points <- figdat %>%
  select(c(id, session, block, trial, points)) %>%
  mutate(points = str_sub(points, 3, -3)) %>%
  separate_rows(points, sep = "\\), \\(") %>%
  separate(points, c("x", "y"), sep = ", ", convert = TRUE)


# Extract and parse figure segment data

# NOTE: currently will warn/error on linear segments, fix this
segment_cols <- c("start.x", "start.y", "end.x", "end.y", "ctrl.x", "ctrl.y")

segments <- figdat %>%
  select(c(id, session, block, trial, segments)) %>%
  mutate(segments = str_sub(segments, 2, -2)) %>%
  separate_rows(segments, sep = "\\],\\[") %>%
  mutate(segments = str_sub(segments, 2, -2)) %>%
  separate(segments, segment_cols, sep = "[^0-9-.]+", convert = TRUE)


# Extract and parse figure animation data

frames <- figdat %>%
  select(c(id, session, block, trial, frames)) %>%
  mutate(frames = str_sub(frames, 3, -3)) %>%
  separate_rows(frames, sep = "\\), \\(") %>%
  separate(frames, c("x", "y", "time"), sep = ", ", convert = TRUE)


# Extract and parse figure tracing data (from physical trials)

tracings <- figdat %>%
  select(c(id, session, block, trial, tracing)) %>%
  filter(tracing != "NA") %>%
  mutate(tracing = str_sub(tracing, 3, -3)) %>%
  separate_rows(tracing, sep = "\\), \\(") %>%
  separate(tracing, c("x", "y", "time"), sep = ", ", convert = TRUE)



### Learned figure import and parsing ###


#load mapping file to correct ID error
partMap <- read.csv(list.files(
  "./_Data/", pattern = "*.csv",
  full.names = TRUE
)) %>%
  rename(
    recall1=answer.to.first.Q..identified.a.repeating.trajectory.y.n.,
    draw1=genereated.a.trajectory.,
    recall2=answer.to.second.Q..identified.another.repeating.trajectory.y.n.,
    draw2=generated.a.second.trajectory.
  ) %>%
  mutate(
    draw2 = recode_factor(draw2, N="n", Y="y"),
    draw1 = fct_expand(draw1,"n"),
    draw1 = fct_relevel(draw1,"n","y")
  ) %>%
  replace(is.na(.),'n') %>%
  select(-c(Participant.number,X,X.1))


# If any learned figures, coerce those into a data frame too

if (length(learnedfiles) > 0) {

  learned <- map_df(learnedfiles, function(f) {
    tibble(
      fname = gsub("\\.zip", "", basename(f)),
      tracing = read_lines(f)
    )
  })

  learned <- learned %>%
    mutate(fname = gsub("[a-z\\.]", "", fname)) %>%
    separate(fname, c("id", "num"), sep = "___", convert = TRUE) %>%
    arrange(id, num) %>%
    mutate(tracing = str_sub(tracing, 3, -3)) %>%
    separate_rows(tracing, sep = "\\), \\(") %>%
    separate(tracing, c("x", "y", "time"), sep = ", ", convert = TRUE)

} else {

  # If no learned figures, just create empty df for consistency
  learned <- tibble(
    id = integer(), num = integer(),
    x = integer(), y = integer(),
    time = double()
  )

}

learned <- learned %>%
  group_by(id) %>%
  mutate(id=ifelse(id %in% partMap$implicitData.ID,
                   filter(partMap,implicitData.ID==unique(id))$learningData,
                   id)) %>%
  ungroup()
