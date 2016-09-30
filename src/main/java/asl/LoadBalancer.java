package main.java.asl;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.net.InetSocketAddress;
import java.nio.ByteBuffer;
import java.nio.channels.SelectionKey;
import java.nio.channels.Selector;
import java.nio.channels.ServerSocketChannel;
import java.nio.channels.SocketChannel;
import java.util.*;

/**
 * This is the class that takes all incoming requests, hashes them and forwards to the correct MiddlewareComponent(s).
 */
public class LoadBalancer implements Runnable {

    private static final Logger log = LogManager.getLogger(LoadBalancer.class);
    private static final Integer LOG_EVERY_N_REQUESTS = 1;

    private Integer requestCounter;

    private List<MiddlewareComponent> middlewareComponents;
    private Hasher hasher;
    private String address;
    private Integer port;

    private Map<SelectionKey, String> requestMessageBuffer;
    private Map<SelectionKey, Request> keyToRequest;

    LoadBalancer(List<MiddlewareComponent> middlewareComponents, Hasher hasher, String address, Integer port) {
        this.middlewareComponents = middlewareComponents;
        this.hasher = hasher;
        this.address = address;
        this.port = port;
        this.requestMessageBuffer = new HashMap<>();
        this.keyToRequest = new HashMap<>();
        this.requestCounter = 0;
    }

    /**
     * Take one request and add it to the correct queue.
     */
    void handleRequest(Request request, SelectionKey selectionKey) {
        keyToRequest.put(selectionKey, request);
        selectionKey.interestOps(SelectionKey.OP_WRITE);    // TODO
        log.debug("contains after putting? " + keyToRequest.containsKey(selectionKey));

        requestMessageBuffer.remove(selectionKey);

        Integer primaryMachine = hasher.getPrimaryMachine(request.getKey());
        MiddlewareComponent mc = middlewareComponents.get(primaryMachine);

        log.debug("Sending request " + request + " to its primary machine #" + primaryMachine + ".");

        if(request.getType().equals(RequestType.GET)) {
            mc.readQueue.add(request);
        } else {
            mc.writeQueue.add(request);     // DELETE requests also go to the write queue.
        }

        requestCounter++;
        if(requestCounter > 0 && requestCounter % LOG_EVERY_N_REQUESTS == 0) {
            log.info(String.format("Processed %5d requests so far.", requestCounter));
        }
    }

    @Override
    public void run() {

        log.info("Load balancer started.");

        try {
            // Selector: multiplexor of SelectableChannel objects
            Selector selector = Selector.open(); // selector is open here

            // ServerSocketChannel: selectable channel for stream-oriented listening sockets
            ServerSocketChannel serverSocketChannel = ServerSocketChannel.open();
            InetSocketAddress inetSocketAddress = new InetSocketAddress(address, port);

            // Binds the channel's socket to a local address and configures the socket to listen for connections
            serverSocketChannel.bind(inetSocketAddress);

            // Adjusts this channel's blocking mode.
            serverSocketChannel.configureBlocking(false);

            int ops = serverSocketChannel.validOps();
            SelectionKey selectionKey = serverSocketChannel.register(selector, ops, null);

            while(true) {
                log.debug("Waiting for a new connection...");
                // Select a set of keys whose corresponding channels are ready for I/O operations
                selector.select();

                // Token representing the registration of a SelectableChannel with a Selector
                Set<SelectionKey> selectedKeys = selector.selectedKeys();
                Iterator<SelectionKey> selectionKeyIterator = selectedKeys.iterator();


                while (selectionKeyIterator.hasNext()) {
                    SelectionKey myKey = selectionKeyIterator.next();

                    if(keyToRequest.containsKey(myKey) && keyToRequest.get(myKey).hasResponse()) {
                        // If request has response, then write it.

                        String response = keyToRequest.get(myKey).getResponse();
                        keyToRequest.remove(myKey);

                        SocketChannel client = (SocketChannel) myKey.channel();

                        // Populate buffer
                        ByteBuffer buffer = ByteBuffer.allocate(2 * MiddlewareMain.MAX_VALUE_SIZE);
                        buffer.put(response.getBytes());
                        buffer.flip();

                        log.debug("Trying to respond to client " + client);

                        // Write buffer
                        while(buffer.hasRemaining()) {
                            client.write(buffer);

                            int result = client.write(buffer);
                            log.debug("Responding to request " + this + ": writing '" + Util.unEscapeString(response) + "'; result: " + result);
                        }

                        myKey.interestOps(SelectionKey.OP_READ);
                        //client.close();
                    }

                    if ((myKey.isValid() && myKey.isAcceptable())) {
                        // If this key's channel is ready to accept a new socket connection
                        SocketChannel client = serverSocketChannel.accept();

                        // Adjusts this channel's blocking mode to false
                        client.configureBlocking(false);

                        // Operation-set bit for read operations
                        client.register(selector, SelectionKey.OP_READ);
                        log.debug("Connection accepted: " + client.getLocalAddress());


                    } else if (myKey.isValid() && myKey.isReadable()) {
                        // If this key's channel is ready for reading

                        SocketChannel client = (SocketChannel) myKey.channel();
                        ByteBuffer buffer = ByteBuffer.allocate(MiddlewareMain.MAX_VALUE_SIZE);
                        client.read(buffer);
                        String message = new String(buffer.array());
                        message = message.substring(0, buffer.position());

                        if(!requestMessageBuffer.containsKey(myKey)) {
                            log.debug("SEEING KEY FOR FIRST TIME: " + myKey);
                            // If this is the first time we hear from this connection
                            RequestType requestType = Request.getRequestType(message);

                            if (requestType == RequestType.GET) {
                                // TODO assuming we get the whole GET or DELETE message in one chunk
                                Request r = new Request(message, client);
                                log.debug(r.getType() + " message received: " + r);

                                handleRequest(r, myKey);
                            } else if (requestType == RequestType.SET) {
                                // We may need to wait for the second line in the SET request.
                                requestMessageBuffer.put(myKey, message);
                                //log.debug("Got a part of SET request [" + Util.unEscapeString(message) + "], waiting for more.");
                            }
                        } else {
                            log.debug("ADDING STUFF TO KEY: " + myKey);
                            // If we have something already from this connection
                            String updatedMessage = requestMessageBuffer.get(myKey) + message;
                            requestMessageBuffer.put(myKey, updatedMessage);
                        }

                        // If we already have the whole message, we can create a Request.
                        if(requestMessageBuffer.containsKey(myKey) &&
                                Request.isCompleteSetRequest(requestMessageBuffer.get(myKey))) {
                            log.debug("KEY IS COMPLETE: " + myKey);
                            String fullMessage = requestMessageBuffer.get(myKey);
                            Request r = new Request(fullMessage, client);
                            log.debug(r.getType() + " message received: " + r);
                            handleRequest(r, myKey);
                        }

                    }
                    selectionKeyIterator.remove();
                }
            }

        } catch (Exception ex) {
            log.error(ex);
            throw new RuntimeException(ex);
        }
    }

}
