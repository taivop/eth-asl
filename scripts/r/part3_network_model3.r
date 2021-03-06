source("scripts/r/common.r")
source("scripts/r/ms3_common.r")

# ---- Directories and files ----
output_dir <- "results/analysis/part3_network"
octave_dir_base <- paste0(output_dir, "/mva")
data_source_dir <- "results/replication"

# ---- Helper function ----
normalise_request_log_df <- function(df) {
  
  first_request_time <- min(df$timeCreated)
  last_request_time <- max(df$timeCreated)
  DROP_TIMES_BEFORE = first_request_time + 2 * 60 * 1000
  DROP_TIMES_AFTER = last_request_time - 2 * 60 * 1000
  
  df2 <- df %>% filter(timeCreated > DROP_TIMES_BEFORE &
                          timeCreated <= DROP_TIMES_AFTER)
  return(df2)
}

model_inputs <- function(requests, mss) {
  
  requests_get <- requests %>% filter(type == "GET")
  requests_set <- requests %>% filter(type == "SET")
  
  T_seconds <- (max(requests$timeDequeued)-min(requests$timeDequeued)) / 1000 # total time 
  tps_WW <- nrow(requests_set) / SAMPLING_RATE / T_seconds / num_servers
  
  res <- list()
  res$tLB_get <- mean(requests_get$timeEnqueued-requests_get$timeCreated)
  res$tLB_set <- mean(requests_set$timeEnqueued-requests_set$timeCreated)
  res$tRW <- mean(requests_get$timeReturned-requests_get$timeDequeued)
  res$tWW <- mean(requests_set$timeReturned-requests_set$timeDequeued) #1/tps_WW * 1000
  
  rt_middleware_get <- mean(requests_get$timeReturned-requests_get$timeCreated)
  rt_middleware_set <- mean(requests_set$timeReturned-requests_set$timeCreated)
  rt_memaslap_get <- mss$mean_response_time_get
  rt_memaslap_set <- mss$mean_response_time_set
  
  res$tNW_get <- (rt_memaslap_get-rt_middleware_get)/2
  res$tNW_set <- (rt_memaslap_set-rt_middleware_set)/2
  
  return(res)
}

exp_dir <- "./results/replication/S5_R1_rep5"

memaslap_file <- paste0(exp_dir, "/memaslap_stats.csv")
requests_file <- paste0(exp_dir, "/request.log")

# ---- Reading data ----
memaslap <- file_to_df(memaslap_file) %>% mutate(repetition=0)
requests <- file_to_df(requests_file, sep=",") %>%
  normalise_request_log_df()
requests_get <- requests %>% filter(type=="GET")
requests_set <- requests %>% filter(type=="SET")

# ---- Preprocessing ----
dir_name_regex <- paste0("/S(\\d)_R(\\d)_rep(\\d)$")
result_params <- as.data.frame(str_match(exp_dir, dir_name_regex))

dir_name_end <- substr(result_params$V1, 2,
                       nchar(as.character(result_params$V1)))
num_servers = as.numeric(as.character(result_params$V2))
num_replication = as.numeric(as.character(result_params$V3))
num_repetition = result_params$V4
num_threads = 32
num_clients = 180
perc_writes = 5
prop_writes = perc_writes / 100
SAMPLING_RATE <- 1/10

mss <- memaslap_summary(memaslap) %>%
  mutate(type="actual")

inputs <- model_inputs(requests, mss) %>% as.data.frame()

# ---- Model results ----
octave_output_dir <- paste0(octave_dir_base, "/model3/", dir_name_end)
system(paste0("mkdir -p ", octave_output_dir))
octave_output_file <- paste0(octave_output_dir, "/results.mat")
arg_list <- paste(octave_output_file,
                  num_servers, num_threads, num_clients, perc_writes,
                  inputs$tNW_get, inputs$tNW_set,
                  inputs$tLB_get, inputs$tLB_set,
                  inputs$tWW, inputs$tRW,
                  collapse=" ")
system(paste0("octave scripts/oct/mva3_main.m ", arg_list))
mva <- readMat(octave_output_file)

K <- ncol(mva$U) # number of nodes in the network
ind_RW = 3:(3+num_servers-1) # ReadWorker devices
ind_WW = (3+num_servers):(3+2*num_servers-1) # WriteWorker devices
ind_network = c(1, K)

predicted <- list()
predicted$type <- "predicted"
predicted$throughput <- sum(mva$X[1:2,1])
predicted$throughput_readworkers <- sum(mva$X[1,ind_RW])
predicted$throughput_writeworkers <- sum(mva$X[2,ind_WW])
predicted$mean_response_time_get <- sum((mva$R * mva$V)[1,])*1000
predicted$mean_response_time_set <- sum((mva$R * mva$V)[2,])*1000
predicted$mean_response_time <-
  (1 - prop_writes) * predicted$mean_response_time_get +
  prop_writes * predicted$mean_response_time_set
predicted$mean_response_time_readworker <- sum((mva$R * mva$V)[,ind_RW])*1000
predicted$mean_response_time_writeworker <- sum((mva$R * mva$V)[,c(ind_WW)])*1000
predicted$mean_response_time_lb_get <- mva$R[1,2] * 1000
predicted$mean_response_time_lb_set <- mva$R[2,2] * 1000
predicted$util_lb_get <- mva$U[1,2]
predicted$util_lb_set <- mva$U[2,2]
predicted$util_readworker <- mva$U[1,3]
predicted$util_writeworker <- mva$U[2,K-1]
predicted$items_network_get <- sum(mva$Q[1,ind_network])
predicted$items_network_set <- sum(mva$Q[2,ind_network])
predicted$items_lb_get <- mva$Q[1,2]
predicted$items_lb_set <- mva$Q[2,2]
predicted$items_readworkers <- sum(mva$Q[1,ind_RW])
predicted$items_writeworkers <- sum(mva$Q[2,ind_WW])

# ---- Actual results ----
tps_get <- (1-prop_writes) * mss$tps_mean # TODO this is an estimate -- could get precise!
tps_set <- prop_writes * mss$tps_mean
actual <- as.list(mss %>% rename(throughput=tps_mean))
actual$throughput_readworkers <- tps_get
actual$throughput_writeworkers <- tps_set
actual$mean_response_time_readworker <- mean(requests_get$timeReturned-requests_get$timeEnqueued)
actual$mean_response_time_writeworker <- mean(requests_set$timeReturned-requests_set$timeEnqueued)
actual$mean_response_time_lb_get <- NA
actual$mean_response_time_lb_set <- NA
actual$util_lb_get <- tps_get * inputs$tLB_get / 1000 # utilization law
actual$util_lb_set <- tps_set * inputs$tLB_set / 1000 # utilization law
actual$util_readworker <- (tps_get / num_servers / num_threads) * inputs$tRW / 1000 # utilization law
actual$util_writeworker <- (tps_set / num_servers) * inputs$tWW / 1000 # utilization law # TODO fucked up somehow
actual$items_network_get <- 2 * inputs$tNW_get / 1000 * tps_get # Little's law (33-02)
actual$items_network_set <- 2 * inputs$tNW_set / 1000 * tps_set
actual$items_lb_get <- NA
actual$items_lb_set <- NA
actual$items_readworkers <- actual$mean_response_time_readworker / 1000 * tps_get
actual$items_writeworkers <- actual$mean_response_time_writeworker / 1000 * tps_set

# ---- Analysis ----

comparison <- as.data.frame(actual) %>%
  select(-std_response_time) %>%
  rbind(as.data.frame(predicted)) %>%
  mutate(servers=num_servers, threads=num_threads, clients=num_clients,
         writes=perc_writes, replication=num_replication,
         repetition=num_repetition)
comparison

comparisons_to_save <- comparison %>%
  select(-servers, -threads, -clients, -writes, -replication, -repetition,
         -mean_response_time_lb_get, -mean_response_time_lb_set,
         -items_lb_get, -items_lb_set) %>%
  melt(id.vars=c("type")) %>%
  dcast(variable ~ type) %>%
  select(variable, predicted, actual)
comparison_table <- xtable(comparisons_to_save, caption="Parameters of the system calculated using MVA. \\texttt{lb} stands for \\linkmain{LoadBalancer}. The throughput and number of items in workers is given as the total over all threads. The response time of and number of items in \\linkmain{LoadBalancer} have been left out of the table because they were extremely low.",
                             label="tbl:part3:comparison_table",
                             digits=c(NA, NA, 2, 2),
                             align="|l|l|r|r|")
print.xtable(comparison_table, file=paste0(output_dir, "/comparison_table.txt"),
             size="\\fontsize{9pt}{10pt}\\selectfont",
             table.placement="h")

# Bottleneck analysis
Z <- 0 # waiting time
X <- max(mva$X)
D <- mva$U / mva$X
D_sum <- sum(D, na.rm=TRUE)  # sum(D[1,ind_RW]) + sum(D[2,ind_WW]) + sum(D[2,])
D_max <- max(D, na.rm=TRUE)
throughput_constant <- num_servers * ((1-prop_writes) * 1/D[1,3] + prop_writes * 1/D[2,8])
responsetime_constant_get <- D[1,3] * 1000 # ms
responsetime_constant_set <- D[2,8] * 1000 # ms



# Time breakdown: actual vs predicted
data1 <- comparison %>%
  select(mean_response_time_readworker, mean_response_time_writeworker,
         mean_response_time_get, mean_response_time_set, type) %>%
  melt(id.vars=c("type"))

ggplot(data1, aes(x=type, y=value, fill=type)) +
  geom_bar(stat="identity") +
  facet_wrap(~variable) +
  asl_theme
ggsave(paste0(output_dir, "/graphs/responsetime_actual_vs_predicted.pdf"),
       width=fig_width, height=fig_height)

# Number of items: actual vs predicted
data2_gets <- comparison %>%
  select(items_network_get, items_readworker, type) %>%
  rename(items_network=items_network_get,
         items_worker=items_readworker) %>%
  melt(id.vars=c("type")) %>%
  mutate(request_type="GET")
data2_sets <- comparison %>%
  select(items_network_set, items_writeworker, type) %>%
  rename(items_network=items_network_set,
         items_worker=items_writeworker) %>%
  melt(id.vars=c("type")) %>%
  mutate(request_type="SET")
data2 <- data2_gets %>%
  rbind(data2_sets)
  
ggplot(data2, aes(x=type, y=value, fill=type)) +
  geom_bar(stat="identity") +
  facet_wrap(~request_type + variable, nrow=1) +
  asl_theme
ggsave(paste0(output_dir, "/graphs/items_actual_vs_predicted.pdf"),
       width=fig_width, height=fig_height)

# Utilisation: actual vs predicted
data3 <- comparison %>%
  select(util_lb_get:util_writeworker, type) %>%
  melt(id.vars=c("type"))

ggplot(data3, aes(x=type, y=value, fill=type)) +
  geom_bar(stat="identity") +
  facet_wrap(~variable, nrow=1) +
  xlab("Value") +
  ylab("Utilisation") +
  asl_theme +
  theme(legend.position="none")
ggsave(paste0(output_dir, "/graphs/utilisation_actual_vs_predicted.pdf"),
       width=fig_width, height=fig_height / 2)