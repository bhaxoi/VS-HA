// Klasse zur Speicherung des aktuellen Zustands des Clients 
class ClientSession {
    String sender = "unknown";
    String receiver = "unknown";
    boolean inDataMode = false;
    StringBuilder emailBody = new StringBuilder();
}

public class SMTPServer {
    public static void main(String[] args) {
        try {
            Selector selector = Selector.open();
            ServerSocketChannel serverSocket = ServerSocketChannel.open();
            serverSocket.bind(new InetSocketAddress(6332));
            serverSocket.configureBlocking(false);
            serverSocket.register(selector, SelectionKey.OP_ACCEPT);

            System.out.println("SMTP Server started. Listening on port 6332...");

            while (true) {
                selector.select();
                Set<SelectionKey> selectedKeys = selector.selectedKeys();
                Iterator<SelectionKey> iter = selectedKeys.iterator();

                while (iter.hasNext()) {
                    SelectionKey key = iter.next();

                    if (key.isAcceptable()) {
                        ServerSocketChannel server = (ServerSocketChannel) key.channel();
                        SocketChannel client = server.accept();
                        client.configureBlocking(false);

                        // Für jeden Client wird eine eigene Session erstellt und zugeordnet 
                        client.register(selector, SelectionKey.OP_READ, new ClientSession());
                        System.out.println("New client connected successfully!");

                        String greeting = "220 localhost SMTP NIO Server Ready\r\n";
                        client.write(ByteBuffer.wrap(greeting.getBytes("US-ASCII")));
                    }
                    else if (key.isReadable()) {
                        SocketChannel client = (SocketChannel) key.channel();
                        // Zugehörige Session (Zustand des Clients) abrufen
                        ClientSession session = (ClientSession) key.attachment();

                        ByteBuffer buffer = ByteBuffer.allocate(2048);
                        int bytesRead = client.read(buffer);

                        if (bytesRead == -1) {
                            System.out.println("Client disconnected.");
                            client.close();
                        } else {
                            buffer.flip();
                            byte[] bytes = new byte[buffer.remaining()];
                            buffer.get(bytes);
                            String clientMessage = new String(bytes, "US-ASCII");

                            System.out.print("Client says: " + clientMessage);

                            // Wenn der Client im DATA-Modus ist, wird der Inhalt als Mailtext gespeichert
                            if (session.inDataMode) {
                                session.emailBody.append(clientMessage);
                                
                                // SMTP-Regel: Die Mail endet mit einer einzelnen Zeile mit einem Punkt
                                if (session.emailBody.toString().endsWith("\r\n.\r\n") || clientMessage.trim().equals(".")) {
                                    
                                    // Mail gemäß Vorgaben in eine Datei speichern
                                    saveEmailToFile(session);

                                    // Zustand zurücksetzen für die nächste Mail
                                    session.inDataMode = false;
                                    session.emailBody.setLength(0); 
                                    
                                    String response = "250 Message accepted for delivery\r\n";
                                    client.write(ByteBuffer.wrap(response.getBytes("US-ASCII")));
                                }
                            } 
                            // Wenn nicht im DATA-Modus, normale SMTP-Kommandos verarbeiten
                            else {
                                String response = "";
                                String upperMessage = clientMessage.toUpperCase().trim();

                                if (upperMessage.startsWith("HELO")) {
                                    response = "250 Hello\r\n";
                                } 
                                else if (upperMessage.startsWith("MAIL FROM:")) {
                                    // Absender speichern 
                                    session.sender = clientMessage.substring(clientMessage.indexOf(":") + 1).trim();
                                    response = "250 Sender OK\r\n";
                                } 
                                else if (upperMessage.startsWith("RCPT TO:")) {
                                    // Empfänger speichern 
                                    session.receiver = clientMessage.substring(clientMessage.indexOf(":") + 1).trim();
                                    response = "250 Recipient OK\r\n";
                                } 
                                else if (upperMessage.equals("DATA")) {
                                    // In den Datenmodus wechseln
                                    session.inDataMode = true; 
                                    response = "354 Start mail input; end with <CRLF>.<CRLF>\r\n";
                                } 
                                else if (upperMessage.startsWith("HELP")) {
                                    response = "214 This is a simple Java NIO SMTP Server\r\n";
                                } 
                                else if (upperMessage.startsWith("QUIT")) {
                                    response = "221 Service closing transmission channel\r\n";
                                    client.write(ByteBuffer.wrap(response.getBytes("US-ASCII")));
                                    client.close();
                                    continue; 
                                } 
                                else {
                                    response = "500 Command unrecognized\r\n";
                                }

                                if (client.isOpen()) {
                                    client.write(ByteBuffer.wrap(response.getBytes("US-ASCII")));
                                }
                            }
                        }
                    }
                    iter.remove();
                }
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    // Hilfsmethode zum Speichern der E-Mail in Datei und Ordner
    private static void saveEmailToFile(ClientSession session) {
        try {
            // Ordnername = Empfänger, Dateiname = Absender + ID 
            String receiverDir = session.receiver.replaceAll("[^a-zA-Z0-9@.-]", "_"); 
            String senderFile = session.sender.replaceAll("[^a-zA-Z0-9@.-]", "_");
            
            // Zufällige ID zwischen 0 und 9999 
            int messageId = new Random().nextInt(10000); 
            String fileName = senderFile + "_" + messageId;

            Path dirPath = Paths.get(receiverDir);
            if (!Files.exists(dirPath)) {
                Files.createDirectories(dirPath); // Ordner für Empfänger erstellen
            }

            Path filePath = dirPath.resolve(fileName);

            // Dateioperationen sollen mit Channel erfolgen (nicht mit Streams)
            try (FileChannel fileChannel = FileChannel.open(filePath, StandardOpenOption.CREATE, StandardOpenOption.WRITE)) {
                ByteBuffer buffer = ByteBuffer.wrap(session.emailBody.toString().getBytes("US-ASCII"));
                fileChannel.write(buffer);
            }
            
            System.out.println("Email saved to file: " + filePath.toString());

        } catch (IOException e) {
            System.err.println("Failed to save email: " + e.getMessage());
        }
    }
}
