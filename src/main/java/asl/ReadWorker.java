package main.java.asl;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.io.IOException;
import java.util.Queue;
import java.util.concurrent.BlockingQueue;

/**
 * This class is responsible for reading values from memcached and returning responses to the client.
 */
class ReadWorker implements Runnable {

    private Integer componentId;
    private Integer threadId;
    private BlockingQueue<Request> readQueue;
    private MemcachedConnection connection;

    private static final Logger log = LogManager.getLogger(ReadWorker.class);

    ReadWorker(Integer componentId, Integer threadId, BlockingQueue<Request> readQueue) {
        this.componentId = componentId;
        this.threadId = threadId;
        this.readQueue = readQueue;
        this.connection = new MemcachedConnection();

        // TODO start connection to our memcached server using MemcachedConnection
        // TODO
    }

    @Override
    public void run() {
        try {
            log.info(String.format("%s started.", getName()));

            while (true) {
                if (!readQueue.isEmpty()) {
                    try {
                        Request r = readQueue.take();
                        log.info(getName() + " processing request " + r);
                        // TODO actually do something with the request
                        connection.sendRequest(r);
                    } catch (InterruptedException ex) {
                        log.error(ex);
                    }
                }
            }
        } catch(Exception ex) {
            log.error(ex);
            throw new RuntimeException(ex);
        }
    }

    public String getName() {
        return String.format("c%dr%d", componentId, threadId);
    }
}
