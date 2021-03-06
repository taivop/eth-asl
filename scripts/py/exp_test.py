import logging
from experiment import Experiment

# region ---- Logging ----
LOG_FORMAT = '%(asctime)-15s [%(name)s] - %(message)s'
LOG_LEVEL = logging.INFO
formatter = logging.Formatter(LOG_FORMAT)

ch = logging.StreamHandler()
ch.setLevel(LOG_LEVEL)
ch.setFormatter(formatter)

log = logging.getLogger(__name__)
log.setLevel(LOG_LEVEL)
log.addHandler(ch)
# endregion

# region ---- Experimental setup ----
S = 7
R = 7
T = 1

e = Experiment()

e.start_experiment("results/testing",
                   update_and_install=False,
                   experiment_runtime=10,
                   runtime_buffer=1,
                   replication_factor=R,
                   num_threads_in_pool=T,
                   num_memaslaps=3,
                   num_memcacheds=S,
                   hibernate_at_end=False)
