source("scripts/r/common.r")

# ---- Parse command line args ----
args <- commandArgs(trailingOnly=TRUE)
if(length(args) == 0) {
  result_dir_base <- "results/writes"
} else if(length(args) == 1) {
  result_dir_base <- args[1]
} else {
  stop("Arguments: [<results_directory>]")
}

# ---------------------------
# ---- HELPER FUNCTIONS -----
# ---------------------------

memaslap_summary <- function(df) {
  DROP_TIMES_BEFORE = 2 * 60 # How many seconds in the beginning we want to drop
  DROP_TIMES_AFTER = max((df %>% filter(type=="t"))$time) - 2 * 60
  
  df2 <- df %>%
    mutate(min=min/1000, max=max/1000, avg=avg/1000, std=std/1000) %>%
    filter(type=="t" & time > DROP_TIMES_BEFORE & time <= DROP_TIMES_AFTER)
  
  means <- df2 %>%
    group_by(request_type) %>%
    summarise(mean_response_time=sum(ops*avg)/sum(ops))
  
  response_times <- df2 %>%
    group_by(time) %>%
    summarise(mean_response_time=sum(ops*avg)/sum(ops)) %>%
    select(time, mean_response_time)
  
  res <- list()
  tps_summed <- df2 %>% group_by(time, repetition) %>%
    summarise(tps=sum(tps))
  tps_values <- tps_summed$tps
  res$tps_mean <- mean(tps_values)
  res$tps_std <- sd(tps_values)
  two_sided_t_val <- qt(c(.025, .975), df=length(tps_values)-1)[2]
  res$tps_confidence_delta <- two_sided_t_val * res$tps_std/sqrt(length(tps_values))
  res$tps_confidence_delta_rel <- res$tps_confidence_delta / res$tps_mean
  res$mean_response_time_get <- (means %>% filter(request_type=="GET"))$mean_response_time[1]
  res$mean_response_time_set <- (means %>% filter(request_type=="SET"))$mean_response_time[1]
  res$mean_response_time <- (res$mean_response_time_get * sum((df2 %>% filter(request_type=="GET"))$ops) +
    res$mean_response_time_set * sum((df2 %>% filter(request_type=="SET"))$ops)) / sum(df2$ops)
  res$std_response_time <- sqrt(sum(df2$ops * df2$std * df2$std)) / sum(df2$ops)
  
  return(as.data.frame(res))
}

middleware_summary <- function(dfmw) {
  num_requests <- length(dfmw$tAll)
  
  res <- list()
  res$response_time_mean <- mean(dfmw$tAll)
  res$response_time_std <- sd(dfmw$tAll)
  two_sided_t_val <- qt(c(.025, .975), df=num_requests-1)[2]
  res$response_time_confidence_delta <-
    two_sided_t_val * res$response_time_std/sqrt(num_requests)
  res$response_time_confidence_delta_rel <-
    res$response_time_confidence_delta / res$response_time_mean
  res$response_time_q01 <- quantile(dfmw$tAll, 0.01)
  res$response_time_q05 <- quantile(dfmw$tAll, 0.05)
  res$response_time_q25 <- quantile(dfmw$tAll, 0.25)
  res$response_time_q50 <- quantile(dfmw$tAll, 0.50)
  res$response_time_q75 <- quantile(dfmw$tAll, 0.75)
  res$response_time_q95 <- quantile(dfmw$tAll, 0.95)
  res$response_time_q99 <- quantile(dfmw$tAll, 0.99)
  res$tLoadBalancer <- mean(dfmw$tLoadBalancer)
  res$tQueue <- mean(dfmw$tQueue)
  res$tWorker <- mean(dfmw$tWorker)
  res$tMemcached <- mean(dfmw$tMemcached)
  res$tReturn <- mean(dfmw$tReturn)
  
  return(as.data.frame(res))
}

file_to_df <- function(file_path, sep=";") {
  if(file.exists(file_path)) {
    df <- read.csv(file_path, header=TRUE, sep=sep)
    result <- df
  } else {
    result <- data.frame()
  }
  return(result)
}

normalise_request_log_df <- function(df) {
  df2 <- df %>%
    mutate(tLoadBalancer=timeEnqueued-timeCreated,
           tQueue=timeDequeued-timeEnqueued,
           tWorker=timeForwarded-timeDequeued,
           tMemcached=timeReceived-timeForwarded,
           tReturn=timeReturned-timeReceived,
           tAll=timeReturned-timeCreated)
  
  first_request_time <- min(df2$timeCreated)
  last_request_time <- max(df2$timeCreated)
  DROP_TIMES_BEFORE = first_request_time + 2 * 60 * 1000
  DROP_TIMES_AFTER = last_request_time - 2 * 60 * 1000
  
  df2 <- df2 %>% filter(timeCreated > DROP_TIMES_BEFORE &
                          timeCreated <= DROP_TIMES_AFTER) %>%
    select(-timeCreated, -timeEnqueued, -timeDequeued, -timeForwarded,
           -timeReceived, -timeReturned)
  return(df2)
}

# ------------------
# ---- FILE IO -----
# ------------------

# ---- Loop over result dirs ----
file_name_regex <- paste0(result_dir_base,
                          "/S(\\d)_R(\\d)_writes(\\d{1,2})_rep([2-4])/memaslap_stats\\.csv$")
unfiltered_files <- list.files(path=".", "memaslap_stats.csv", recursive=TRUE)
filtered_files <- grep(file_name_regex, unfiltered_files, value=TRUE, perl=TRUE)

result_params <- as.data.frame(str_match(filtered_files, file_name_regex))
colnames(result_params) <- c("path", "servers", "replication", "writes", "repetition")
result_params <- result_params  %>%
  mutate(path=as.character(path))
# group_by(clients, threads) %>%
#summarise(paths=paste0(path, collapse=";"))

detailed_results <- NA
results <- NA
mw_results <- NA
sr_combinations <- result_params %>%
  select(servers, replication, writes) %>%
  unique()

for(i in 1:nrow(sr_combinations)) {
  n_servers <- sr_combinations[i,]$servers
  n_replication <- sr_combinations[i,]$replication
  n_writes <- sr_combinations[i,]$writes
  repetitions <- result_params %>%
    filter(servers==n_servers & replication==n_replication & writes==n_writes)
  
  combined_result <- NA
  combined_mw_result <- NA
  for(j in 1:nrow(repetitions)) {
    params <- repetitions[j,]
    print(dirname(params$path))
    rep_id <- params$repetition
    file_path <- params$path
    mw_file_path <- paste0(dirname(file_path), "/request.log")
    repetition_result <- file_to_df(file_path) %>%
      mutate(repetition=rep_id)
    mw_result <- file_to_df(mw_file_path, sep=",") %>%
      mutate(repetition=rep_id) %>%
      normalise_request_log_df()
    
    if(is.na(combined_result)) {
      combined_result <- repetition_result
      combined_mw_result <- mw_result
    } else {
      combined_result <- rbind(combined_result, repetition_result)
      combined_mw_result <- rbind(combined_mw_result, mw_result)
    }
    
    # Save memaslap repetition result separately
    mss <- memaslap_summary(repetition_result) %>%
      mutate(servers=n_servers,
             replication=n_replication,
             writes=n_writes,
             repetition=rep_id)
    if(is.na(detailed_results)) {
      detailed_results <- mss
    } else {
      detailed_results <- rbind(detailed_results, mss)
    }
  }
  
  combined_ms_result_row <- memaslap_summary(combined_result)
  combined_mw_result_row_get <-
    middleware_summary(combined_mw_result %>% filter(type=="GET")) %>%
    mutate(type="GET", servers=n_servers, replication=n_replication,
           writes=n_writes)
  combined_mw_result_row_set <-
    middleware_summary(combined_mw_result %>% filter(type=="SET")) %>%
    mutate(type="SET", servers=n_servers, replication=n_replication,
           writes=n_writes)
  combined_mw_result_row_all <-
    middleware_summary(combined_mw_result) %>%
    mutate(type="all", servers=n_servers, replication=n_replication,
           writes=n_writes)
  
  if(is.na(results)) {
    results <- combined_ms_result_row
    mw_results <- rbind(combined_mw_result_row_get, combined_mw_result_row_set,
                        combined_mw_result_row_all)
  } else {
    results <- rbind(results, combined_ms_result_row)
    mw_results <- rbind(mw_results, 
                        combined_mw_result_row_get, combined_mw_result_row_set,
                        combined_mw_result_row_all)
  }
}

all_results <- cbind(sr_combinations, results) %>%
  right_join(mw_results, by=c("servers", "replication", "writes")) %>%
  mutate(servers=as.numeric(as.character(servers)),
         replication=as.numeric(as.character(replication)),
         writes=as.numeric(as.character(writes))) %>%
  mutate(replication_str=get_replication_factor_vocal(servers, replication),
         servers_str=paste0(servers, " servers"),
         writes_str=get_writes_factor(writes))

write.csv(all_results, file=paste0(result_dir_base, "/all_results.csv"),
          row.names=FALSE)
write.csv(detailed_results, file=paste0(result_dir_base, "/detailed_results.csv"),
          row.names=FALSE)

# ------------------
# ---- PLOTTING ----
# ------------------

# Response time vs R and S
data1 <- all_results
ggplot(data1 %>% filter(type=="GET"),
             aes(x=writes_str, y=response_time_mean, group=1)) +
  geom_ribbon(aes(ymin=response_time_q25,
                  ymax=response_time_q75),
              fill=color_triad1, alpha=0.5) +
  geom_line(aes(y=response_time_q50), color=color_triad1_dark, size=1) +
  geom_errorbar(aes(ymin=response_time_mean-response_time_confidence_delta,
                    ymax=response_time_mean+response_time_confidence_delta),
                color=color_triad2, width=0.2, size=1) +
  geom_point(color=color_dark) +
  geom_line(color=color_dark) +
  facet_wrap(~replication_str+servers_str, nrow=2) +
  ylim(0, NA) +
  ylab("Response time (middleware) [ms]") +
  xlab("Proportion of write requests") +
  ggtitle("GET requests") +
  asl_theme
ggsave(paste0(result_dir_base, "/graphs/response_time_vs_writes_get.pdf"),
       width=fig_width, height=fig_height, device=cairo_pdf)

ggplot(data1 %>% filter(type=="SET"),
             aes(x=writes_str, y=response_time_mean, group=1)) +
  geom_ribbon(aes(ymin=response_time_q25,
                  ymax=response_time_q75),
              fill=color_triad1, alpha=0.5) +
  geom_line(aes(y=response_time_q50), color=color_triad1_dark, size=1) +
  geom_errorbar(aes(ymin=response_time_mean-response_time_confidence_delta,
                    ymax=response_time_mean+response_time_confidence_delta),
                color=color_triad2, width=0.2, size=1) +
  geom_point(color=color_dark) +
  geom_line(color=color_dark) +
  facet_wrap(~replication_str+servers_str, nrow=2) +
  ylim(0, NA) +
  ylab("Response time (middleware) [ms]") +
  xlab("Proportion of write requests") +
  ggtitle("SET requests") +
  asl_theme
ggsave(paste0(result_dir_base, "/graphs/response_time_vs_writes_set.pdf"),
       width=fig_width, height=fig_height*1.7, device=cairo_pdf)

# Proportion of time spent in different parts of system
data3 <- all_results %>%
  select(type, servers_str, replication_str, writes_str, tLoadBalancer:tReturn) %>%
  melt(id.vars=c("type", "servers_str", "replication_str", "writes_str")) %>%
  rename(Component=variable) %>%
  mutate(Component=factor(Component, ordered=TRUE,
                          levels=rev(c("tLoadBalancer", "tQueue", "tWorker", "tMemcached", "tReturn"))))

ggplot(data3 %>% filter(type=="SET"), aes(x=writes_str, y=value, fill=Component, group=1)) +
  geom_bar(stat="identity") +
  facet_wrap(~replication_str+servers_str, nrow=2) +
  xlab("Proportion of write requests") +
  ylab("Time spent [ms]") +
  asl_theme +
  scale_fill_brewer(palette="Set1")
ggsave(paste0(result_dir_base, "/graphs/time_breakdown_vs_writes_set_abs.pdf"),
       width=fig_width, height=fig_height, device=cairo_pdf)

ggplot(data3 %>% filter(type=="SET"), aes(x=writes_str, y=value, fill=Component, group=1)) +
  geom_bar(stat="identity", position="fill") +
  facet_wrap(~replication_str+servers_str, nrow=2) +
  xlab("Proportion of write requests") +
  ylab("Proportion of time spent") +
  asl_theme +
  scale_fill_brewer(palette="Set1")
ggsave(paste0(result_dir_base, "/graphs/time_breakdown_vs_writes_set_rel.pdf"),
       width=fig_width, height=fig_height, device=cairo_pdf)

ggplot(data3 %>% filter(type=="GET"), aes(x=writes_str, y=value, fill=Component, group=1)) +
  geom_bar(stat="identity") +
  facet_wrap(~replication_str+servers_str, nrow=2) +
  xlab("Proportion of write requests") +
  ylab("Time spent [ms]") +
  asl_theme +
  scale_fill_brewer(palette="Set1")
ggsave(paste0(result_dir_base, "/graphs/time_breakdown_vs_writes_get_abs.pdf"),
       width=fig_width, height=fig_height, device=cairo_pdf)

# Throughput
data2 <- all_results %>%
  filter(type=="all")
ggplot(data2, aes(x=writes_str, y=tps_mean, group=1)) +
  geom_errorbar(aes(ymin=tps_mean-tps_confidence_delta,
                    ymax=tps_mean+tps_confidence_delta),
                color=color_triad2, width=0.25, size=0.5) +
  geom_line(color=color_dark) +
  geom_point(color=color_dark) +
  facet_wrap(~replication_str+servers_str, nrow=2) +
  xlab("Number of clients") +
  ylab("Total throughput [requests/s]") +
  ylim(0, NA) +
  asl_theme
ggsave(paste0(result_dir_base, "/graphs/throughput_vs_writes.pdf"),
       width=fig_width, height=fig_height, device=cairo_pdf)

# Performance decrease compared to 1% writes
data3 <- all_results %>%
  group_by(type, servers, replication) %>%
  mutate(relative_performance=response_time_mean/response_time_mean[writes==1],
         confidence_interval=response_time_confidence_delta/response_time_mean[writes==1]) %>%
  select(type, servers_str, replication_str, writes_str, relative_performance,
         confidence_interval)

ggplot(data3 %>% filter(type=="all"), aes(x=writes_str, y=relative_performance, group=1)) +
  geom_errorbar(aes(ymin=relative_performance-confidence_interval,
                    ymax=relative_performance+confidence_interval),
                color=color_triad2, width=0.3, size=1) +
  geom_line(color=color_dark) +
  geom_point(color=color_dark) +
  facet_wrap(~replication_str+servers_str, nrow=2) +
  ylim(0, NA) +
  xlab("Proportion of write requests") +
  ylab("Response time relative to base case ") +
  asl_theme
ggsave(paste0(result_dir_base, "/graphs/relative_performance_all.pdf"),
       width=fig_width, height=fig_height, device=cairo_pdf)

ggplot(data3 %>% filter(type=="SET"), aes(x=writes_str, y=relative_performance, group=1)) +
  geom_errorbar(aes(ymin=relative_performance-confidence_interval,
                    ymax=relative_performance+confidence_interval),
                color=color_triad2, width=0.3, size=1) +
  geom_line(color=color_dark) +
  geom_point(color=color_dark) +
  facet_wrap(~replication_str+servers_str, nrow=2) +
  ylim(0, NA) +
  xlab("Proportion of write requests") +
  ylab("Response time relative to base case ") +
  asl_theme
ggsave(paste0(result_dir_base, "/graphs/relative_performance_set.pdf"),
       width=fig_width, height=fig_height, device=cairo_pdf)

ggplot(data3 %>% filter(type=="GET"), aes(x=writes_str, y=relative_performance, group=1)) +
  geom_errorbar(aes(ymin=relative_performance-confidence_interval,
                    ymax=relative_performance+confidence_interval),
                color=color_triad2, width=0.3, size=1) +
  geom_line(color=color_dark) +
  geom_point(color=color_dark) +
  facet_wrap(~replication_str+servers_str, nrow=2) +
  ylim(0, NA) +
  xlab("Proportion of write requests") +
  ylab("Response time relative to base case ") +
  asl_theme
ggsave(paste0(result_dir_base, "/graphs/relative_performance_get.pdf"),
       width=fig_width, height=fig_height, device=cairo_pdf)  

# Not within confidence interval
not_confident <- all_results %>%
  filter(response_time_confidence_delta_rel > 0.05) %>%
  select(servers, replication, writes, response_time_confidence_delta_rel)

cat(paste0(nrow(data1), " experiments total, ", nrow(not_confident),
           " experiments' response time 95% confidence interval is not within 5% of mean:"))
print(not_confident)

not_confident2 <- all_results %>%
  filter(tps_confidence_delta_rel > 0.05) %>%
  select(servers, replication, writes, tps_confidence_delta_rel)

cat(paste0(nrow(data1), " experiments total, ", nrow(not_confident2),
           " experiments' throughput 95% confidence interval is not within 5% of mean:"))
print(not_confident2)

# Compare middleware and memaslap
data_compare <- all_results %>%
  filter(type=="all") %>%
  rename(memaslap=mean_response_time, middleware=response_time_mean) %>%
  select(writes_str, replication_str, servers_str, memaslap, middleware) %>%
  melt(id.vars=c("replication_str", "servers_str", "writes_str")) %>%
  rename(Measurer=variable)
ggplot(data_compare, aes(x=writes_str, y=value, color=Measurer, group=Measurer)) +
  geom_line() +
  geom_point() +
  facet_wrap(~replication_str+servers_str, nrow=2) +
  ylim(0, NA) +
  xlab("Replication") + ylab("Mean response time") +
  asl_theme
ggsave(paste0(result_dir_base, "/graphs/compare_mw_ms.pdf"),
       width=fig_width, height=fig_height, device=cairo_pdf)

