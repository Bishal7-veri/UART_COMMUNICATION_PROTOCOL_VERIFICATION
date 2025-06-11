

// purpose of transaction class 
// All the inputs and outputs involved in a UART communication.

//An operation type (read/write).

//A method to clone itself, useful for testbenches and scoreboard comparison.


class transaction ;
  typedef enum bit {write = 1'b0, read = 1'b1} oper_type;
  randc oper_type oper;
  
  // randc will generate all possible values of oper_type without repetition
  
  bit rx;
  rand bit [7:0] dintx;
  bit newd;
  bit tx;
  bit [7:0] doutrx;
  bit donetx;
  bit donerx;
  
 function transaction copy();
    copy = new();
    copy.rx = this.rx;
    copy.dintx = this.dintx;
    copy.newd = this.newd;
    copy.tx = this.tx;
    copy.doutrx = this.doutrx;
    copy.donetx = this.donetx;
    copy.donerx = this.donerx;
    copy.oper = this.oper;
  endfunction

endclass

class generator;
  
 transaction tr;
  
  mailbox #(transaction) mbx;
  
  event done;
  
  int count = 0;
  
  event drvnext;
  event sconext;
  
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    tr = new();
  endfunction
  
  
  task run();
  
    repeat(count) begin
      assert(tr.randomize) else $error("[GEN] :Randomization Failed");
      mbx.put(tr.copy);
      $display("[GEN]: Oper : %0s Din : %0d",tr.oper.name(), tr.dintx);
      @(drvnext);
      @(sconext);
    end
    
    -> done;
  endtask
  
  
endclass
 
class driver;
  
  
  virtual uart_if vif;
  
  transaction tr;
  
  mailbox #(transaction) mbx; // mailbox to receive data from the generator
  
  mailbox #(bit [7:0]) mbxds; // mailbox to send data to the scorecard
  
  
  event drvnext;
  
  bit [7:0] din;
  
  
  bit wr = 0;  ///random operation read / write
  bit [7:0] datarx;  ///data rcvd during read
  
  
  
  
  
  function new(mailbox #(bit [7:0]) mbxds, mailbox #(transaction) mbx);
    this.mbx = mbx;
    this.mbxds = mbxds;
   endfunction
  
  
  
  task reset();
    vif.rst <= 1'b1;
    vif.dintx <= 0;
    vif.newd <= 0;
    vif.rx <= 1'b1;
 
    repeat(5) @(posedge vif.uclktx);
    vif.rst <= 1'b0;
    @(posedge vif.uclktx);
    $display("[DRV] : RESET DONE");
    $display("----------------------------------------");
  endtask
  
  
  
  task run();
  
    forever begin
      mbx.get(tr); // getting the generated data from the generator
      
      if(tr.oper == 1'b0)  ////data transmission
          begin
          //           
            @(posedge vif.uclktx);
            vif.rst <= 1'b0;
            vif.newd <= 1'b1;  ///start data sending op
            vif.rx <= 1'b1;
            vif.dintx = tr.dintx;
            @(posedge vif.uclktx);
            vif.newd <= 1'b0;
              ////wait for completion 
            //repeat(9) @(posedge vif.uclktx);
            mbxds.put(tr.dintx);
            $display("[DRV]: Data Sent : %0d", tr.dintx);
             wait(vif.donetx == 1'b1);  
             ->drvnext;  
          end
      
      else if (tr.oper == 1'b1)
               begin
                 
                 @(posedge vif.uclkrx);
                  vif.rst <= 1'b0;
                  vif.rx <= 1'b0;
                  vif.newd <= 1'b0;
                  @(posedge vif.uclkrx);
                  
                 for(int i=0; i<=7; i++) 
                 begin   
                      @(posedge vif.uclkrx);                
                      vif.rx <= $urandom;
                      datarx[i] = vif.rx;                                      
                 end 
                 
                 
                mbxds.put(datarx);
                
                $display("[DRV]: Data RCVD : %0d", datarx); 
                wait(vif.donerx == 1'b1);
                 vif.rx <= 1'b1;
				->drvnext;
                 
 
             end         
  
       
      
    end
    
  endtask
  
endclass

class monitor;
 
  transaction tr;
  
  mailbox #(bit [7:0]) mbx; 
  
  bit [7:0] srx; //////send
  bit [7:0] rrx; ///// recv
  
 
  
  virtual uart_if vif;
  
  
  function new(mailbox #(bit [7:0]) mbx);
    this.mbx = mbx;
    endfunction
  
  task run();
    
    forever begin
     
       @(posedge vif.uclktx);
      if ( (vif.newd== 1'b1) && (vif.rx == 1'b1) ) 
                begin
                  
                  @(posedge vif.uclktx); ////start collecting tx data from next clock tick
                  
              for(int i = 0; i<= 7; i++) 
              begin 
                    @(posedge vif.uclktx);
                    srx[i] = vif.tx;
                    
              end
 
                  
                  $display("[MON] : DATA SEND on UART TX %0d", srx);
                  
                  //////////wait for done tx before proceeding next transaction                
                @(posedge vif.uclktx); //
                  mbx.put(srx); // put sent data to scoreboard
                 
               end
      
      else if ((vif.rx == 1'b0) && (vif.newd == 1'b0) ) 
        begin
          wait(vif.donerx == 1);
          rrx = vif.doutrx;     
          $display("[MON] : DATA RCVD RX %0d", rrx);
          @(posedge vif.uclktx); 
          mbx.put(rrx); // put received data to scoreboard
      end
  end  
endtask
  
 
endclass
 

class scoreboard;
  mailbox #(bit [7:0]) mbxds, mbxms; // creating mailbox for both driver and scoreboard and monitor and scoreboard
  
  bit [7:0] ds; // data for driver 
  bit [7:0] ms; // data for monitor
  
   event sconext;
  
  function new(mailbox #(bit [7:0]) mbxds, mailbox #(bit [7:0]) mbxms);
    this.mbxds = mbxds; // for driver and scoreboard data matching
    this.mbxms = mbxms; // for monitor and scoreboard data matching
  endfunction
  
  task run();
    forever begin
      
      mbxds.get(ds); // get the data of ds for driver and scoreboard
      mbxms.get(ms); // get the data of ms for monitor and scoreboard 
      
      $display("[SCO] : DRV : %0d MON : %0d", ds, ms);
      if(ds == ms) // if data from driver to scoreboard and data from monitor to scoreboard
        $display("DATA MATCHED");
      else
        $display("DATA MISMATCHED");
      
      $display("----------------------------------------");
      
     ->sconext; // event for scoreboard next 
    end
  endtask
  
  
endclass

class environment;
 
    generator gen; // creating constructor for generator
    driver drv; // creating constructor for driver
    monitor mon; // creating constructor for monitor
    scoreboard sco; // creating constructor for scoreboard
  
    
  
    event nextgd; ///gen -> drv
  
    event nextgs;  /// gen -> sco
  
  mailbox #(transaction) mbxgd; ///gen - drv
  
  mailbox #(bit [7:0]) mbxds; /// drv - sco
    
     
  mailbox #(bit [7:0]) mbxms;  /// mon - sco
  
    virtual uart_if vif; // creating virtual dut for the interface 
 
  
  function new(virtual uart_if vif);
       
    mbxgd = new();
    mbxms = new();
    mbxds = new();
    
    gen = new(mbxgd); // linking generator with the mailbox of generator and driver
    drv = new(mbxds,mbxgd); // linking driver with the mailbox of driver and scoreboard and generator and scoreboard
    
    
 
    mon = new(mbxms); // linking monitor with mailbox of monitor and scoreboard
    sco = new(mbxds, mbxms); // linking scoreboard with the mailbox driver and scoreboard and monitor and scoreboard
    
    this.vif = vif;
    drv.vif = this.vif;
    mon.vif = this.vif;
    
    gen.sconext = nextgs; // event after generator and scoreboard
    sco.sconext = nextgs;
    
    gen.drvnext = nextgd; // event after driver and generator
    drv.drvnext = nextgd;
 
  endfunction
  
  task pre_test();
    drv.reset(); // reset
  endtask
  
  task test();
  fork
    gen.run();
    drv.run();
    mon.run();
    sco.run();
  join_any
  endtask
  
  task post_test();
    wait(gen.done.triggered); // finish the program when done is triggered in generator 
    $finish();
  endtask
  
  task run();
    pre_test();
    test();
    post_test();
  endtask
  
  
  
endclass
 
///////////////////////////////////////////
 
 
module tb;
    
  uart_if vif();
  
  uart_top #(1000000, 9600) dut (vif.clk,vif.rst,vif.rx,vif.dintx,vif.newd,vif.tx,vif.doutrx,vif.donetx, vif.donerx);
  
  
  
    initial begin
      vif.clk <= 0;
    end
    
    always #10 vif.clk <= ~vif.clk;
    
    environment env; // creating object for the enviroment class
    
    
    
    initial begin
      env = new(vif); // sending the virtual information data to the enviroment class
      env.gen.count = 5; // setting up the count for generator as 5
      env.run(); // enviroment run 
    end
      
    
    initial begin
      $dumpfile("uart_top.vcd");
      $dumpvars(0,tb);
    end
   
  assign vif.uclktx = dut.utx.uclk; // assigning the clock of virtual interface same as the receiver and transmitter clock.
  assign vif.uclkrx = dut.rtx.uclk;
    
  endmodule
 
 
 
////////////////////////////////////////
 
 





 



