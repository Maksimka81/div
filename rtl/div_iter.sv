module div_iter #(
  parameter XLEN = 16 // Определение параметра ширины данных
)(
  input logic                       clk_i,            // Вход тактового сигнала
  input logic                       arstn_i,          // Асинхронный сброс (активный низкий)

  input  logic [XLEN-1:0]           data1_tdata_i,    // Делимое
  input  logic                      data1_tvalid_i,
  output logic                      data1_tready_o,

  input  logic [XLEN-1:0]           data2_tdata_i,    // Делитель
  input  logic                      data2_tvalid_i,
  output logic                      data2_tready_o,

  output logic [XLEN-1:0]           data_tdata_o,     // Результат деления
  output logic                      data_tvalid_o,
  input  logic                      data_tready_i
);

  // Состояния конечного автомата
  typedef enum logic [2:0] {
       IDLE,
       INIT_REGISTERS,
       DIVISION_STEP,
       RESULT_READY,
       RESTORING
   } div_state_t;

  div_state_t  div_state, div_next_state; // Текущее и следующее состояние
  logic [XLEN-1:0]        operand_a_uns; // Значение делимого
  logic [XLEN-1:0]        operand_b_uns; // Значение делителя
  logic signed [2*XLEN-1:0] P_A_reg;    // Частное и остаток
  //logic signed [2*XLEN-1:0] P_A_temp;   // регистр для хранения предыдущего значения
  logic                    rem_sign;   // Знак остатка
  logic                    div_sign;   // Знак результата деления
  logic [$clog2(XLEN)-1:0] iteration;  // Счетчик итераций

  logic                    sign_a;     // Знак делимого
  logic                    sign_b;     // Знак делителя

  // Определение знаков чисел
  assign sign_a = data1_tdata_i[XLEN-1];
  assign sign_b = data2_tdata_i[XLEN-1];

  // Управление готовностью данных
  assign data_tdata_o =   P_A_reg[XLEN-1:0];
  assign data1_tready_o = (div_state == IDLE);
  assign data2_tready_o = (div_state == IDLE);
  assign data_tvalid_o = (div_state == RESULT_READY);
  
  always_ff @(posedge clk_i or negedge arstn_i) begin
    if (~arstn_i) begin
      div_state <= IDLE;
    end else begin
      div_state <= div_next_state;
    end
  end

  // Комбинационная логика для определения следующего состояния
  always_comb begin
    div_next_state = div_state;

    case (div_state)
      IDLE: begin
        if (data1_tvalid_i && data2_tvalid_i) begin
          div_next_state = INIT_REGISTERS;
        end
      end
      INIT_REGISTERS: begin
        div_next_state = DIVISION_STEP;
      end
      DIVISION_STEP: begin
        if (iteration == 1) begin
          div_next_state = RESTORING;
        end
      end
      RESTORING: begin
          div_next_state <= RESULT_READY;
      end
      RESULT_READY: begin
        if (data_tready_i) begin
          div_next_state = IDLE;
        end
      end
      default: begin
        div_next_state = IDLE;
      end
    endcase
  end

  logic [XLEN-1:0] operand_a;
  assign operand_a = sign_a ? (~{1'b1, data1_tdata_i} + 1) : {1'b0, data1_tdata_i};
  logic [XLEN-1:0] operand_b;
  assign operand_b =  sign_b ? (~{1'b1, data2_tdata_i} + 1) : {1'b0, data2_tdata_i};

   // Вычислительная логика
  always_ff @(posedge clk_i or negedge arstn_i) begin
    if (~arstn_i) begin
      P_A_reg       <= '0;
      operand_a_uns <= '0;
      operand_b_uns <= '0;
      div_sign      <= '0;
      rem_sign      <= '0;
      iteration     <= '0;
    end else begin
      case (div_state)
        INIT_REGISTERS: begin
          operand_a_uns <= operand_a; // Преобразование делимого в положительное значение
          operand_b_uns <= operand_b; // Преобразование делителя в положительное значение
          rem_sign <= sign_a; // Установка знака остатка
          div_sign <= sign_a ^ sign_b; // Вычисление знака результата деления
          iteration <= 4'hF;
          P_A_reg[XLEN-1:0]      <= {operand_a[XLEN-2:0], {1'b0}};
          P_A_reg[2*XLEN-1:XLEN] <= {{(XLEN-1){1'b0}}, operand_a[XLEN-1]} - operand_b[XLEN-1:0]; 
        end
        DIVISION_STEP: begin
        begin
          iteration <= iteration - 1;
          if (P_A_reg[2*XLEN-1]) begin // Восстановление
            P_A_reg[2*XLEN-1:XLEN] <= P_A_reg[2*XLEN-1:XLEN-1] + operand_b_uns[XLEN-1:0];
            P_A_reg[XLEN-1:0] <= {P_A_reg[XLEN-2:0], 1'b0};
          end else begin
            P_A_reg[2*XLEN-1:XLEN] <= P_A_reg[2*XLEN-1:XLEN-1] - operand_b_uns[XLEN-1:0];
            P_A_reg[XLEN-1:0] <= {P_A_reg[XLEN-2:0], 1'b1};
          end 
        end
        end
           RESTORING: begin  // Без отдельной стадии  востановления работает не коррректно. Из-за потери последней итерации
          if (P_A_reg[2*XLEN-1]) begin
            P_A_reg[2*XLEN-1:XLEN] <= P_A_reg[2*XLEN-1:XLEN-1] + operand_b_uns[XLEN-1:0];
            P_A_reg[XLEN-1:0] <= {P_A_reg[XLEN-2:0], 1'b0};
          end
          else begin
            P_A_reg[XLEN-1:0] <= {P_A_reg[XLEN-2:0], 1'b1};
          end
        end

        default: begin
        end
      endcase
    end
  end

endmodule
/* begin
          iteration <= iteration - 1;
          P_A_temp <= P_A_reg;
          P_A_reg[2*XLEN-1:XLEN] <= P_A_reg[2*XLEN-1:XLEN] - operand_b_uns;
          if (P_A_reg[2*XLEN-1]) begin 
            P_A_reg <= P_A_temp;
            P_A_reg[XLEN-1:0] <= {P_A_reg[XLEN-2:0], 1'b0};
          end else begin
            P_A_reg[XLEN-1:0] <= {P_A_reg[XLEN-2:0], 1'b1};
          end
        end*/
        /*
          iteration <= iteration - 1;
          if (P_A_reg[2*XLEN-1]) begin // Восстановление
            P_A_reg[2*XLEN-1:XLEN] <= P_A_reg[2*XLEN-1:XLEN] + operand_b_uns;
            P_A_reg[XLEN-1:0] <= {P_A_reg[XLEN-2:0], 1'b0};                    
          end else begin
            P_A_reg[2*XLEN-1:XLEN] <= P_A_reg[2*XLEN-1:XLEN] - operand_b_uns;
            P_A_reg[XLEN-1:0] <= {P_A_reg[XLEN-2:0], 1'b1};
          end */



  // 
    // 5)
  // Чтобы не заморачиваться параметры можно писать через конструкцию "enum", где все переменные будут кодироваться в двоичке по порядку.
  // Так ты сможешь использовать во всех кейсах только fsm_state который будет принимать значение, в соответствии с текущим состоянием.
  // Пример:

  // enum logic [1:0] { IDLE, ..., ..., ..., RESULT_READY } fsm_state (div_state у тебя);

  // Конец примера.

  // 6)
  // Тут мне не очень нравится, что ты смешал вычислительную логику с логикой переходов конечного автомат.
  // На практике обычно делают так:
  // Пример:

  /////////////////////////
  //         FSM         //
  /////////////////////////

  // это описание самого регистра, который хранит состояние конечного автомата (div_state у тебя):

  // always_ff @( posedge clk_i ) begin
  //   if( ~arstn_i ) begin
  //     div_state <= ...
  //   end
  //   else begin
  //     div_state <= ...
  //   end
  // end

  // это описание комбинационной логики, которая, в зависимости от каких-то внешних факторов, переключает сигнал (div_next_state у тебя его пока нету):

  // always_comb begin
  //   div_next_state = div_state;

  //   case ( d_state )

  //     IDLE: begin
  //       if ( ... )
  //         div_next_state = ...;
  //     end

  //     .............................
  //     .............................
  //     .............................

  //     RESULT_READY: begin
  //       if ( ... )
  //         div_next_state = ...;
  //     end

  //   endcase
  // end

  // Конец примера.

  // 7)
  // Вычислительную логику лучше реализовать в отдельном always_ff() блоке.

  // 8)
  // Касательно P_A_reg, по какой-то причине он оказался в двух разных always_ff() блоках. По хорошему так быть не должно.
  // Инициализация значения и сами вычисления с регистром должны находиться одном блоке always_ff().
  // Пример:

  // always_ff @( posedge clk_i ) begin
  //   if( ~arstn_i ) begin
  //     P_A_reg <= '0;
  //     ..._reg <= '0;
  //   end
  //   else begin
  //     P_A_reg <= ...;
  //     ..._reg <= ...;
  //   end
  // end

  // 9)
  // Что касается алгоритма, то в целом вектор мысли правильный, нужно только оптимизнуть это.
  // У тебя на данный момент отдельная стадия а КА используется для вычисления частичного остатка, а ещё одна нужна для восстановления.
  // Это не самое оптимальное решение. Тебе надо подумать, как можно объединить эти стадии в одну.


  // NEW:
  // 11) Тут всё вообще чётко с конечным автоматом теперь. По моим прикидкам меньше 4-х стадий сделать затруднительно.
  //     Вдобавок у теря разрядность регистра div_state падает до 2-х бит, что оптимальнее.
   // Логика переходов состояний конечного автомата
     // NEW: 12)
  // Из мелкого что вижу: лучше обращаться к срезу регистра через параметр, допустим XLEN, который будет означать какую-то стандартную ширину данных в устройстве,
  // вместо конструкции типа: P_A_reg[31:16] <= P_A_reg[31:16] + operand_b_uns; Так появится возможность сделать твой модуль параметризуемым.
  // Параметры можно описывать как в самом модуле, так и в отдельном фале package (_pkg).
  // Пример:

          // package systolic_array_pkg;

          //   parameter LEN = 16;
          //   parameter COL = 8;
          //   parameter ROW = 8;
          //   parameter STR = 1; // 1 - 1x[8x8] input stream / 2 - 2x[8x8] input streams

          // endpackage

  // Конец примера.

  // Чтобы заюзать такой файл в твоём модуле нужно дописать в шапке модуля следующую конструкцию:
  // Пример:

          // module draco_syst_mac
          //   import systolic_array_pkg::LEN; // либо, чтобы перечислить все элементы сразу используется: import systolic_array_pkg::*;
          //   import systolic_array_pkg::STR;
          //   (
          //   input  logic clk_i,
          //   input  logic arstn_i,

  // Конец примера.

  // Чтобы объявить параметры внутри твоего модуля (их можно будет задавать снаружи модуля, главное чтобы внутри были объявлены)
  // используется следующая конструция:
  // Пример:

          // module draco_syst_buf
          // #(
          //   parameter LEN = "",  // в данном случае параметр пуст, чтобы можно было задать его снаружи
          //   parameter STR = 2    // в данном случае параметр задан внутри модуля (по-моему если ты их не очистишь и подашь другие параметры снаружи, то наружный параметр приоритетнее)
          // )(
          //   input  logic                           clk_i,
          //   input  logic                           arstn_i,

          //   input  logic                           enable_i,

          //   input  logic                           sync_i,
          //   input  logic signed [STR-1:0][LEN-1:0] buf_i,

          //   output logic                           sync_o,
          //   output logic signed [STR-1:0][LEN-1:0] buf_o
          // );

  // Конец примера.

  // Чтобы задать параметры снаружи нужно добавить их в инстанс модуля:
  // Пример:

          // weight input buf generation:
          // for ( i = 1; i <= COL-1; i++ ) begin : m_i_buf_i
          //   for ( j = 0; j <= i-1; j++ ) begin : m_i_buf_j
          //     draco_syst_buf #(
          //       .LEN          ( LEN                 ),
          //       .STR          ( STR                 )
          //     ) draco_buf_m_i (
          //       .clk_i        ( clk_i               ),
          //       .arstn_i      ( arstn_i             ),

          //       .enable_i     ( enable_i            ),

          //       .sync_i       ( s_io_buf_i [i][j]   ),
          //       .buf_i        ( m_io_buf_i [i][j]   ),

          //       .sync_o       ( s_io_buf_i [i][j+1] ),
          //       .buf_o        ( m_io_buf_i [i][j+1] )
          //     );
          //   end
          // end

  // Конец примера.
