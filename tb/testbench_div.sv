module testbench_div;

logic        clk_i;
logic        arstn_i;                         
logic [15:0] data1_tdata_i;  
logic        s_data_tvalid_i;  // AXI-Stream на вход
logic        s_data_tready_o;  // AXI-Stream на вход
logic [15:0] data2_tdata_i;  
logic [15:0] data_tdata_o;   
logic        data_tvalid_o;  
logic        data_tready_i;  

div_iter DUT (
      .clk_i         (clk_i),
      .arstn_i       (arstn_i),
      .data1_tdata_i (data1_tdata_i),
      .data1_tvalid_i(s_data_tvalid_i),
      .data1_tready_o(s_data_tready_o),
      .data2_tdata_i (data2_tdata_i),
      .data2_tvalid_i(s_data_tvalid_i),
      .data2_tready_o(s_data_tready_o),
      .data_tdata_o  (data_tdata_o),
      .data_tvalid_o (data_tvalid_o),
      .data_tready_i (data_tready_i)
);

parameter CLK_PERIOD = 10;
// Генерация тактового сигнала
initial begin
    clk_i <= 0;
    forever begin
        #(CLK_PERIOD/2) clk_i <= ~clk_i;
    end
end

// Пакет и mailbox'ы
typedef struct {
    logic [15:0] tdata;
    logic [15:0] data1;
    logic [15:0] data2;
} packet;

mailbox#(packet) in_mbx  = new();
mailbox#(packet) out_mbx = new();

//---------------------------------
// Методы
//---------------------------------

// Генерация сигнала сброса
task reset();
    arstn_i <= 0;
    #(CLK_PERIOD);
    arstn_i <= 1;
endtask

// Таймаут теста
task timeout();
    repeat(10000) @(posedge clk_i);
    $stop();
endtask

// Генерация входных воздействий
task reset_master();
    wait(~arstn_i);
    s_data_tvalid_i <= 0;
    data1_tdata_i <= 0;
    data2_tdata_i <= 0;
    wait(arstn_i);
endtask

task drive_master(int delay = 0);
    repeat(delay) @(posedge clk_i);
    s_data_tvalid_i <= 1;
    data1_tdata_i <= 10;
    data2_tdata_i <= 2;
    do begin
        @(posedge clk_i);
    end while(~(s_data_tready_o));
    s_data_tvalid_i <= 0;
endtask

task reset_slave();
    wait(~arstn_i);
    data_tready_i <= 0;
    wait(arstn_i);
endtask

task drive_slave(int delay = 0);
    repeat(delay) @(posedge clk_i);
    data_tready_i <= 1;
    @(posedge clk_i);
    data_tready_i <= 0;
endtask

// Мониторинг входов
task monitor_master();
    packet p;
    forever begin
        @(posedge clk_i);
        if(s_data_tvalid_i & s_data_tready_o) begin
            p.data1 = data1_tdata_i;
            p.data2 = data2_tdata_i;
            in_mbx.put(p);
        end
    end
endtask

// Мониторинг выходов
task monitor_slave();
    packet p;
    forever begin
        @(posedge clk_i);
        if(data_tvalid_o & data_tready_i) begin
            p.tdata  = data_tdata_o;
            out_mbx.put(p);
        end
    end
endtask

// Проверка 
task check(); 
    packet in_p, out_p;
    forever begin
        in_mbx.get(in_p);
        out_mbx.get(out_p);
        if(out_p.tdata !== (in_p.data1 / in_p.data2)) begin
            $error("%0t Invalid TDATA: Real1: %0d, Real2: %0d, Expected: %0d",
                $time(), out_p.tdata, in_p.data1, in_p.data2, in_p.data1 / in_p.data2  );
        end 
    end
endtask 

// ----------------
// ВЫПОЛНЕНИЕ
// ----------------
initial begin
    reset();
end

initial begin
    reset_master();
    @(posedge clk_i);
    repeat(10) begin
        drive_master($urandom_range(0, 10));
    end
    $stop();
end

initial begin
    reset_slave();
    @(posedge clk_i);
    forever begin
        drive_slave($urandom_range(0, 10));
    end
end

// Мониторинг
initial begin
    wait(arstn_i);
    monitor_master();
end

initial begin
    wait(arstn_i);
    monitor_slave();
end

// Проверка
initial begin
    check();
end

// Таймаут
initial begin
    timeout();
end

endmodule