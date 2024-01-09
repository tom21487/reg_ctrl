// Constraint random verification testbench using SystemVerilog 2005.

// Transaction object
// Used to instantiate test cases with random parameters.
class reg_item;
    // This is the base transaction object that will be used
    // in the environment to initiate new transactions and 
    // capture transactions at DUT interface
    rand 	bit [7:0] 	addr;
    rand 	bit [15:0] 	wdata;
    bit [15:0] 	rdata;
    rand 	bit 		wr;
    
    // This function allows us to print contents of the data packet
    // so that it is easier to track in a logfile
    function void print(string tag="");
        $display ("T=%0t [%s] addr=0x%0h wr=%0d wdata=0x%0h rdata=0x%0h", 
            $time, tag, addr, wr, wdata, rdata);
    endfunction
endclass

// Driver
// The driver is responsible for driving transactions to the DUT 
// All it does is to get a transaction from the mailbox if it is 
// available and drive it out into the DUT interface.
class driver;
    virtual reg_if vif;
    event drv_done; // Event-driven concurrency (instead of thread-driven).
                    // I feel like this event is unused.
    mailbox drv_mbx;

    task run();
        $display ("T=%0t [Driver] starting ...", $time);
        @ (posedge vif.clk);
        
        // Try to get a new transaction every time and then assign 
        // packet contents to the interface. But do this only if the 
        // design is ready to accept new transactions
        forever begin
            reg_item item;
            
            $display ("T=%0t [Driver] waiting for item ...", $time);
            drv_mbx.get(item);      
	    item.print("Driver");
            vif.sel <= 1; // Select device.
            vif.addr 	<= item.addr;
            vif.wr 	<= item.wr;
            vif.wdata <= item.wdata;
            @ (posedge vif.clk);
            while (!vif.ready)  begin
                $display ("T=%0t [Driver] wait until ready is high", $time);
                @(posedge vif.clk);
            end

            // When transfer is over, raise the done event
            vif.sel <= 0; // De-select device.
            ->drv_done;
        end
    endtask
endclass

// Monitor
// The monitor has a virtual interface handle with which it can monitor
// the events happening on the interface. It sees new transactions and then
// captures information into a packet and sends it to the scoreboard
// using another mailbox.
class monitor;
    virtual reg_if vif;
    mailbox scb_mbx; 		// Mailbox connected to scoreboard
    
    task run();
        $display ("T=%0t [Monitor] starting ...", $time);
        
        // Check forever at every clock edge to see if there is a 
        // valid transaction and if yes, capture info into a class
        // object and send it to the scoreboard when the transaction 
        // is over.
        forever begin
            @ (posedge vif.clk);
            if (vif.sel) begin
                reg_item item = new;
                item.addr = vif.addr;
                item.wr = vif.wr;
                item.wdata = vif.wdata;

                if (!vif.wr) begin
                    // Wait a clock for ready to go high.
                    @(posedge vif.clk);
        	    item.rdata = vif.rdata;
                end
                item.print("Monitor");
                scb_mbx.put(item);
            end
        end
    endtask
endclass

// Scoreboard
// The scoreboard is responsible to check data integrity. Since the design
// stores data it receives for each address, scoreboard helps to check if the
// same data is received when the same address is read at any later point
// in time. So the scoreboard has a "memory" element which updates it
// internally for every write operation.
class scoreboard;
    mailbox scb_mbx;
    
    reg_item refq[256];
    
    task run();
        forever begin
            reg_item item;
            scb_mbx.get(item);
            item.print("Scoreboard");

            // Write
            if (item.wr) begin
                if (refq[item.addr] == null)
                    refq[item.addr] = new;
                refq[item.addr] = item;
                $display ("T=%0t [Scoreboard] Store addr=0x%0h wr=0x%0h data=0x%0h", $time, item.addr, item.wr, item.wdata);
            end

            // Read
            if (!item.wr) begin
                // 1. Check first time reads.
                if (refq[item.addr] == null)
                    if (item.rdata != 'h1234)
              	        $display ("T=%0t [Scoreboard] ERROR! First time read, addr=0x%0h exp=1234 act=0x%0h",
                            $time, item.addr, item.rdata);
          	    else
          		$display ("T=%0t [Scoreboard] PASS! First time read, addr=0x%0h exp=1234 act=0x%0h",
                    	    $time, item.addr, item.rdata);
                // 2. Check other reads.
                else
                    // The scoreboard only checks that the data read at an address is the data that you wrote to that address.
                    // The timing of the ready signal is handled by the driver (wait until ready is high).
                    if (item.rdata != refq[item.addr].wdata)
                        $display ("T=%0t [Scoreboard] ERROR! addr=0x%0h exp=0x%0h act=0x%0h",
                            $time, item.addr, refq[item.addr].wdata, item.rdata);
                    else
                        $display ("T=%0t [Scoreboard] PASS! addr=0x%0h exp=0x%0h act=0x%0h", 
                            $time, item.addr, refq[item.addr].wdata, item.rdata);
            end
        end
    endtask
endclass

// Environment
// The environment is a container object simply to hold all verification 
// components together. This environment can then be reused later and all
// components in it would be automatically connected and available for use
// This is an environment without a generator.
class env;
    driver 			d0; 		// Driver to design
    monitor 			m0; 		// Monitor from design
    scoreboard 		        s0; 		// Scoreboard connected to monitor
    mailbox 			scb_mbx; 	// Top level mailbox for SCB <-> MON
                                                //                scoreboard <-> monitor
                                                // Recall that a mailbox is a thread-safe queue
    virtual reg_if vif;	// Virtual interface handle
    // ChatGPT: A virtual interface handle is a variable that can be assigned a reference to an instance of an interface. The virtual keyword is used to declare such a handle, allowing it to refer to objects of both the base interface type and any of its derived types.
    // The reference for vif is set in module tb's initial begin block. I.e. the actual interface object is instantiated in module tb.

    // Instantiate all testbench components
    function new();
        d0 = new; // Driver has no constructor.
        m0 = new; // Monitor has no constructor.
        s0 = new; // Scoreboard has no constructor.
        scb_mbx = new(); // mailbox's constructor is new(int bound = 0).
    endfunction

    // Assign handles and start all components so that 
    // they all become active and wait for transactions to be
    // available
    virtual task run();
        // Driver, monitor, environment, testbench all share the same virtual interface handle.
        d0.vif = vif;
        m0.vif = vif;
        // Monitor and scoreboard share the same mailbox.
        // This is different than the mailbox shared between class driver and class test
        m0.scb_mbx = scb_mbx;
        s0.scb_mbx = scb_mbx;
        
        fork // Spawns three separate threads.
    	    s0.run();
	    d0.run();
    	    m0.run();
        join_any // Allow main thread to continue execution if any of the child threads finish.
        // Using 'join' instead of 'join_any' also works.
    endtask
endclass

// Test
// an environment without the generator and hence the stimulus should be 
// written in the test. 
class test;
    env e0;
    mailbox drv_mbx; // mailbox = thread-safe queue, if put() and get() happen on the same delta cycle then the ordering is mostly arbitrary (i.e. an ordering to prevent deadlock will be preferred whenever possible).

    function new();
        drv_mbx = new(); // new() here means to invoke the constructor of a dynamically allocated object.
        e0 = new();
    endfunction
    
    virtual task run(); // virtual means that the task can be overridden by a child class.
        e0.d0.drv_mbx = drv_mbx; // environment's driver's mailbox.
        
        fork
    	    e0.run();
        join_none // Allow the main thread to keep running while the child threads are also running.
        // Must be 'join_none' instead of 'join' otherwise will hang on "T=30 [Driver] waiting for item ..."
        // This is because 'join_none' makes env::run() and apply_stim() execute in parallel.

        apply_stim();
    endtask
    
    virtual task apply_stim();
        reg_item item;
        
        $display ("T=%0t [Test] Starting stimulus ...", $time);
        item = new; // Create a new instance of a class that doesn't have a constructor.
        item.randomize() with { addr == 8'haa; wr == 1; };
        drv_mbx.put(item);
        
        item = new;
        item.randomize() with { addr == 8'haa; wr == 0; };
        drv_mbx.put(item);
    endtask
endclass

// Interface for abstraction (hide complexity from users and only show them relevant information).
// https://chipverify.com/systemverilog/systemverilog-interface and
// A logic has 4 states { 0, 1, X, Z }
// A bit has 2 states { 0, 1 }, X and Z show up as 0
// Unlike classes, when interfaces are instantiated you don't need to use new because interfaces are purely abstract.
// The interface allows verification components to access DUT signals
// using a virtual interface handle.
// It is used so that [module tb] [class env] [class driver] [class monitor] all share the same IO packet.
interface reg_if (input bit clk);
    logic rstn;
    logic [7:0] addr;
    logic [15:0] wdata;
    logic [15:0] rdata;
    logic 		wr;
    logic 		sel;
    logic 		ready;
endinterface

// Testbench top
// Top level testbench contains the interface, DUT and test handles which 
// can be used to start test components once the DUT comes out of reset. Or
// the reset can also be a part of the test class in which case all you need
// to do is start the test's run method.
module tb;
    reg clk;
    
    always #10 clk = ~clk; // Clock period = 20 ns
    reg_if _if (clk);

    // Instatiate DUT.
    reg_ctrl u0 ( .clk (clk),
        .addr (_if.addr),
        .rstn(_if.rstn),
        .sel  (_if.sel),
        .wr (_if.wr),
        .wdata (_if.wdata),
        .rdata (_if.rdata),
        .ready (_if.ready));

    initial begin
        // The test contains the environment, which contains the driver, monitor and scoreboard.
        test t0; // was new_test t0;

        // Reset the DUT.
        clk <= 0;
        _if.rstn <= 0;
        _if.sel <= 0;
        #20 _if.rstn <= 1;

        t0 = new; // new creates an instance of a class, new() is used to allocated memory for an array or dynamic data structure.
        t0.e0.vif = _if; // The test's environment's virtual interface handle points to the interface we instantiated in this module.
        t0.run(); // this does environment::run() and apply_stim()
        
        // Once the main stimulus is over, wait for some time
        // until all transactions are finished and then end 
        // simulation. Note that $finish is required because
        // there are components that are running forever in 
        // the background like clk, monitor, driver, etc
        #200 $finish;
    end
    
    // Simulator dependent system tasks that can be used to 
    // dump simulation waves.
    initial begin
        $dumpvars;
        $dumpfile("dump.vcd");
    end
endmodule
