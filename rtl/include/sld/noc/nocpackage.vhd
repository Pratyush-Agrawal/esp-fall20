-- Copyright (c) 2011-2019 Columbia University, System Level Design Group
-- SPDX-License-Identifier: Apache-2.0

library ieee;
use ieee.std_logic_1164.all;

use work.esp_global.all;

package nocpackage is

-------------------------------------------------------------------------------
-- RTL NOC constants and type
--
-- Addressing is XY; X: from left to right, Y: from top to bottom
--
-- Check the module "router" in router.vhd for details on routing algorithm
--
-------------------------------------------------------------------------------


  -- Header fields
  --
  -- Let W be the global constant ARCH_BITS
  --
  -- |W+1        W|W-1     W-5|W-6    W-10|W-11   W-15|W-16   W-20|W-21     W-23|W-24      W-27|W-28       5|4   0|
  -- |  PREAMBLE  |   Src Y   |   Src X   |   Dst Y   |   Dst X   |  Msg. type  |   Reserved   |  [Unused]  |LEWSN|
  --

  constant HEADER_ROUTE_L : natural := 4;
  constant HEADER_ROUTE_E : natural := 3;
  constant HEADER_ROUTE_W : natural := 2;
  constant HEADER_ROUTE_S : natural := 1;
  constant HEADER_ROUTE_N : natural := 0;

  constant PREAMBLE_WIDTH      : natural := 2;
  constant YX_WIDTH            : natural := 5;
  constant MSG_TYPE_WIDTH      : natural := 3;
  constant RESERVED_WIDTH      : natural := 4;
  constant NEXT_ROUTING_WIDTH  : natural := 5;
  constant NOC_FLIT_SIZE       : natural := PREAMBLE_WIDTH + ARCH_BITS;
  constant MISC_NOC_FLIT_SIZE  : natural := PREAMBLE_WIDTH + 32;

  subtype local_yx is std_logic_vector(2 downto 0);
  subtype noc_preamble_type is std_logic_vector(PREAMBLE_WIDTH-1 downto 0);
  subtype noc_msg_type is std_logic_vector(MSG_TYPE_WIDTH-1 downto 0);
  subtype noc_flit_type is std_logic_vector(NOC_FLIT_SIZE-1 downto 0);
  subtype misc_noc_flit_type is std_logic_vector(33 downto 0);
  subtype reserved_field_type is std_logic_vector(RESERVED_WIDTH-1 downto 0);

  type noc_flit_vector is array (natural range <>) of noc_flit_type;
  type misc_noc_flit_vector is array (natural range <>) of misc_noc_flit_type;

  constant noc_flit_pad : std_logic_vector(NOC_FLIT_SIZE - MISC_NOC_FLIT_SIZE - 1 downto 0) := (others => '0');

  -- Preamble encoding
  constant PREAMBLE_HEADER : noc_preamble_type := "10";
  constant PREAMBLE_TAIL   : noc_preamble_type := "01";
  constant PREAMBLE_BODY   : noc_preamble_type := "00";
  constant PREAMBLE_1FLIT  : noc_preamble_type := "11";

  -- -- Message type encoding
  -- -- Cachable data plane 1 -> request messages
  constant REQ_GETS_W   : noc_msg_type := "000";  --Get Shared (word)
  constant REQ_GETM_W   : noc_msg_type := "001";  --Get Modified (word)
  constant REQ_PUTS     : noc_msg_type := "010";  --Put Shared/Exclusive
  constant REQ_PUTM     : noc_msg_type := "011";  --Put Modified
  constant REQ_GETS_B   : noc_msg_type := "100";  --Get Shared (Byte)
  constant REQ_GETS_HW  : noc_msg_type := "101";  --Get Shared (Half Word)
  constant REQ_GETM_B   : noc_msg_type := "110";  --Get Modified (Byte)
  constant REQ_GETM_HW  : noc_msg_type := "111";  --Get Modified (Half word)
  -- Cachable data plane 2 -> forwarded messages
  constant FWD_GETS       : noc_msg_type := "000";
  constant FWD_GETM       : noc_msg_type := "001";
  constant FWD_INV        : noc_msg_type := "010";  --Invalidation
  constant FWD_PUT_ACK    : noc_msg_type := "011";  --Put Acknowledge
  constant FWD_GETM_NOCOH : noc_msg_type := "100";  --Recall on exclusive/modified
  constant FWD_INV_NOCOH  : noc_msg_type := "101";  --Recall on shared
  -- Cachable data plane 3 -> response messages
  constant RSP_DATA     : noc_msg_type := "000";  --CacheLine
  constant RSP_EDATA    : noc_msg_type := "001";  --Cache Line (Exclusive)
  constant RSP_INV_ACK  : noc_msg_type := "010";  --Invalidation Acknowledge
  -- [LLC|Non]-Coherent DMA request plane 6 and response plane 4
  constant DMA_TO_DEV    : noc_msg_type := "001";
  constant DMA_FROM_DEV  : noc_msg_type := "010";
  constant RSP_DATA_DMA  : noc_msg_type := "011";  --CacheLine (DMA)
  constant RSP_P2P       : noc_msg_type := "100";
  constant REQ_P2P       : noc_msg_type := "101";
  constant REQ_DMA_READ  : noc_msg_type := "110";  -- Read coherent with LLC
  constant REQ_DMA_WRITE : noc_msg_type := "111";  -- Write coherent with LLC
  -- Configuration plane 5 -> RD/WR registers
  constant REQ_REG_RD   : noc_msg_type := "000";
  constant REQ_REG_WR   : noc_msg_type := "001";
  constant AHB_RD       : noc_msg_type := "010";
  constant AHB_WR       : noc_msg_type := "011";
  constant IRQ_MSG      : noc_msg_type := "100";
  constant RSP_REG_RD   : noc_msg_type := "101";
  constant RSP_AHB_RD   : noc_msg_type := "110";
  constant INTERRUPT    : noc_msg_type := "111";

  constant ROUTE_NOC3 : std_logic_vector(1 downto 0) := "01";
  constant ROUTE_NOC4 : std_logic_vector(1 downto 0) := "10";
  constant ROUTE_NOC5 : std_logic_vector(1 downto 0) := "11";

  -- Ports routing encoding
  -- 4 = Local tile
  -- 3 = East
  -- 2 = West
  -- 1 = South
  -- 0 = North

  -- 0 = AN; 1 = CB
  constant FLOW_CONTROL : integer := 0;
  -- FIFOs depth
  constant ROUTER_DEPTH : integer := 4;

  type yx_vec is array (natural range <>) of std_logic_vector(2 downto 0);

  -- WARNING: The following constants and types must be changed to scale up;
  --          We need to hardcode this value because of VHDL limitations, but
  --          the *_MAX and *_NUM values are not limited in practice.
  --          These values should match those set in utils/socmap/
  constant MEM_MAX_NUM : integer := GLOB_MEM_MAX_NUM;
  constant CPU_MAX_NUM : integer := GLOB_CPU_MAX_NUM;
  constant TILES_MAX_NUM : integer := GLOB_TILES_MAX_NUM;

  type tile_mem_info is record
    x     : local_yx;
    y     : local_yx;
    haddr : integer;
    hmask : integer;
  end record;

  constant tile_mem_info_none : tile_mem_info := (
    x => (others => '0'),
    y => (others => '0'),
    haddr => 16#000#,
    hmask => 16#fff#
    );

  type tile_mem_info_vector is array (natural range <>) of tile_mem_info;
  type mem_attribute_array is array (0 to MEM_MAX_NUM - 1) of integer;
  type cpu_attribute_array is array (0 to CPU_MAX_NUM - 1) of integer;
  type tile_attribute_array is array (0 to TILES_MAX_NUM - 1) of integer;

  -- Components
  component fifo0
    generic (
      depth : integer;
      width : integer);
    port (
      clk      : in  std_logic;
      rst      : in  std_logic;
      rdreq    : in  std_logic;
      wrreq    : in  std_logic;
      data_in  : in  std_logic_vector(width-1 downto 0);
      empty    : out std_logic;
      full     : out std_logic;
      data_out : out std_logic_vector(width-1 downto 0));
  end component;

  component fifo2
    generic (
      depth : integer;
      width : integer);
    port (
      clk         : in  std_logic;
      rst         : in  std_logic;
      rdreq       : in  std_logic;
      wrreq       : in  std_logic;
      data_in     : in  std_logic_vector(width-1 downto 0);
      empty       : out std_logic;
      full        : out std_logic;
      atleast_4slots  : out std_logic;
      exactly_3slots  : out std_logic;
      data_out    : out std_logic_vector(width-1 downto 0));
  end component;

  component inferred_async_fifo
    generic (
      g_data_width : natural := NOC_FLIT_SIZE;
      g_size       : natural := 6);
    port (
      rst_n_i    : in  std_logic := '1';
      clk_wr_i   : in  std_logic;
      we_i       : in  std_logic;
      d_i        : in  std_logic_vector(g_data_width-1 downto 0);
      wr_full_o  : out std_logic;
      clk_rd_i   : in  std_logic;
      rd_i       : in  std_logic;
      q_o        : out std_logic_vector(g_data_width-1 downto 0);
      rd_empty_o : out std_logic);
  end component;

  -- Helper functions
  function get_origin_y (
    constant flit_sz : integer;
    flit : noc_flit_type)
    return local_yx;

  function get_origin_x (
    constant flit_sz : integer;
    flit : noc_flit_type)
    return local_yx;

  function get_msg_type (
    constant flit_sz : integer;
    flit : noc_flit_type)
    return noc_msg_type;

  function get_preamble (
    constant flit_sz : integer;
    flit : noc_flit_type)
    return noc_preamble_type;

  function get_reserved_field (
    constant flit_sz : integer;
    flit : noc_flit_type)
    return reserved_field_type;

  function get_unused_msb_field (
    constant flit_sz : integer;
    flit : noc_flit_type)
    return std_ulogic;

  function is_gets (
    msg : noc_msg_type)
    return boolean;

  function is_getm (
    msg : noc_msg_type)
    return boolean;

  function create_header (
    constant flit_sz : integer;
    local_y           : local_yx;
    local_x           : local_yx;
    remote_y          : local_yx;
    remote_x          : local_yx;
    msg_type          : noc_msg_type;
    reserved          : reserved_field_type)
    return std_logic_vector;

  function narrow_to_large_flit (
    narrow_flit : misc_noc_flit_type)
    return noc_flit_type;

  function large_to_narrow_flit (
    large_flit : noc_flit_type)
    return misc_noc_flit_type;

  -- IRQ snd packet (Header + 2 flits):
  -- Payload 1
  -- |31    12|11    8|7          7|6        6|5      5|4      4|3   0|
  -- | unused | index | pwdsetaddr | forceerr | rstrun | resume | irl |
  -- Payload 2
  -- |31         2|1      0|
  -- | pwdnewaddr | unused |

  -- IRQ ack packet (Header + 1 flit):
  -- Payload 1
  -- |31    12|11    8|7   7|6    6|5   5|4      4|3   0|
  -- | unused | index | err | fpen | pwd | intack | irl |

  constant IRQ_IRL_MSB        : integer := 3;
  constant IRQ_IRL_LSB        : integer := 0;
  constant IRQ_RESUME_BIT     : integer := 4;
  constant IRQ_RSTRUN_BIT     : integer := 5;
  constant IRQ_FORCEERR_BIT   : integer := 6;
  constant IRQ_PWDSETADDR_BIT : integer := 7;
  constant IRQ_INDEX_LSB      : integer := 8;
  constant IRQ_INDEX_MSB      : integer := 11;

  constant IRQ_PWDNEWADDR_MSB : integer := 31;
  constant IRQ_PWDNEWADDR_LSB : integer := 2;

  constant IRQ_INTACK_BIT : integer := 4;
  constant IRQ_PWD_BIT    : integer := 5;
  constant IRQ_FPEN_BIT   : integer := 6;
  constant IRQ_ERR_BIT    : integer := 7;


end nocpackage;

package body nocpackage is

  function get_origin_y (
    constant flit_sz : integer;
    flit : noc_flit_type)
    return local_yx is
    variable ret : local_yx;
  begin  -- get_origin_y
    ret := (others => '0');
    ret := flit(flit_sz - PREAMBLE_WIDTH - YX_WIDTH + 2 downto flit_sz - PREAMBLE_WIDTH - YX_WIDTH);
    return ret;
  end get_origin_y;

  function get_origin_x (
    constant flit_sz : integer;
    flit : noc_flit_type)
    return local_yx is
    variable ret : local_yx;
  begin  -- get_origin_x
    ret := (others => '0');
    ret := flit(flit_sz - PREAMBLE_WIDTH - 2*YX_WIDTH + 2 downto flit_sz - PREAMBLE_WIDTH - 2*YX_WIDTH);
    return ret;
  end get_origin_x;

  function get_msg_type (
    constant flit_sz : integer;
    flit : noc_flit_type)
    return noc_msg_type is
    variable msg : noc_msg_type;
  begin
    msg := (others => '0');
    msg := flit(flit_sz - PREAMBLE_WIDTH - 4*YX_WIDTH - 1 downto
                flit_sz - PREAMBLE_WIDTH - 4*YX_WIDTH - MSG_TYPE_WIDTH);
    return msg;
  end get_msg_type;

  function get_preamble (
    constant flit_sz : integer;
    flit : noc_flit_type)
    return noc_preamble_type is
    variable ret : noc_preamble_type;
  begin
    ret := flit(flit_sz - 1 downto flit_sz - PREAMBLE_WIDTH);
    return ret;
  end get_preamble;

  function get_reserved_field (
    constant flit_sz : integer;
    flit : noc_flit_type)
    return reserved_field_type is
    variable ret : reserved_field_type;
  begin
    ret := flit(flit_sz - PREAMBLE_WIDTH - 4*YX_WIDTH - MSG_TYPE_WIDTH - 1 downto
                flit_sz - PREAMBLE_WIDTH - 4*YX_WIDTH - MSG_TYPE_WIDTH - RESERVED_WIDTH);
    return ret;
  end get_reserved_field;

  function get_unused_msb_field (
    constant flit_sz : integer;
    flit : noc_flit_type)
    return std_ulogic is
    variable ret : std_ulogic;
  begin
    ret := flit(flit_sz - PREAMBLE_WIDTH - 4*YX_WIDTH - MSG_TYPE_WIDTH - RESERVED_WIDTH - 1);
    return ret;
  end get_unused_msb_field;


  function is_gets (
    msg : noc_msg_type)
    return boolean is
  begin
    if msg = REQ_GETS_W or msg = REQ_GETS_HW or msg = REQ_GETS_B then
      return true;
    else
      return false;
    end if;
  end is_gets;

  function is_getm (
    msg : noc_msg_type)
    return boolean is
  begin
    if msg = REQ_GETM_W or msg = REQ_GETM_HW or msg = REQ_GETM_B then
      return true;
    else
      return false;
    end if;
  end is_getm;

  function create_header (
    constant flit_sz : integer;
    local_y           : local_yx;
    local_x           : local_yx;
    remote_y          : local_yx;
    remote_x          : local_yx;
    msg_type          : noc_msg_type;
    reserved          : reserved_field_type)
    return std_logic_vector is
    variable header : std_logic_vector(flit_sz - 1 downto 0);
    variable go_left, go_right, go_up, go_down : std_logic_vector(NEXT_ROUTING_WIDTH - 1 downto 0);
  begin  -- create_header
    header := (others => '0');
    header(flit_sz - 1 downto
           flit_sz - PREAMBLE_WIDTH) := PREAMBLE_HEADER;
    header(flit_sz - PREAMBLE_WIDTH - 1 downto
           flit_sz - PREAMBLE_WIDTH - YX_WIDTH) := "00" & local_y;
    header(flit_sz - PREAMBLE_WIDTH - YX_WIDTH - 1 downto
           flit_sz - PREAMBLE_WIDTH - 2*YX_WIDTH) := "00" & local_x;
    header(flit_sz - PREAMBLE_WIDTH - 2*YX_WIDTH - 1 downto
           flit_sz - PREAMBLE_WIDTH - 3*YX_WIDTH) := "00" & remote_y;
    header(flit_sz - PREAMBLE_WIDTH - 3*YX_WIDTH - 1 downto
           flit_sz - PREAMBLE_WIDTH - 4*YX_WIDTH) := "00" & remote_x;
    header(flit_sz - PREAMBLE_WIDTH - 4*YX_WIDTH - 1 downto
           flit_sz - PREAMBLE_WIDTH - 4*YX_WIDTH - MSG_TYPE_WIDTH) := msg_type;
    header(flit_sz - PREAMBLE_WIDTH - 4*YX_WIDTH - MSG_TYPE_WIDTH - 1 downto
           flit_sz - PREAMBLE_WIDTH - 4*YX_WIDTH - MSG_TYPE_WIDTH - RESERVED_WIDTH) := reserved;

    if local_x < remote_x then
      go_right := "01000";
    else
      go_right := "10111";
    end if;

    if local_x > remote_x then
      go_left := "00100";
    else
      go_left := "11011";
    end if;

    if local_y < remote_y then
      header(NEXT_ROUTING_WIDTH - 1 downto 0) := "01110" and go_left and go_right;
    else
      header(NEXT_ROUTING_WIDTH - 1 downto 0) := "01101" and go_left and go_right;
    end if;

    if local_y = remote_y and local_x = remote_x then
      header(NEXT_ROUTING_WIDTH - 1 downto 0) := "10000";
    end if;

    return header;
  end create_header;

  function narrow_to_large_flit (
    narrow_flit : misc_noc_flit_type)
    return noc_flit_type is
    variable ret : noc_flit_type;
    variable preamble : noc_preamble_type;
  begin
    ret := (others => '0');
    preamble := get_preamble(MISC_NOC_FLIT_SIZE, noc_flit_pad & narrow_flit);

    if preamble = PREAMBLE_HEADER or preamble = PREAMBLE_1FLIT then
      ret(NOC_FLIT_SIZE - 1 downto NOC_FLIT_SIZE - MISC_NOC_FLIT_SIZE + NEXT_ROUTING_WIDTH) :=
        narrow_flit(MISC_NOC_FLIT_SIZE - 1 downto NEXT_ROUTING_WIDTH);
      ret(NEXT_ROUTING_WIDTH - 1 downto 0) := narrow_flit(NEXT_ROUTING_WIDTH - 1 downto 0);
    else
      ret(NOC_FLIT_SIZE - 1 downto NOC_FLIT_SIZE - PREAMBLE_WIDTH) :=
        narrow_flit(MISC_NOC_FLIT_SIZE - 1 downto MISC_NOC_FLIT_SIZE - PREAMBLE_WIDTH);
      ret(MISC_NOC_FLIT_SIZE - PREAMBLE_WIDTH - 1 downto 0) :=
        narrow_flit(MISC_NOC_FLIT_SIZE - PREAMBLE_WIDTH - 1 downto 0);
    end if;

    return ret;
  end narrow_to_large_flit;

  function large_to_narrow_flit (
    large_flit : noc_flit_type)
    return misc_noc_flit_type is
    variable ret : misc_noc_flit_type;
    variable preamble : noc_preamble_type;
  begin
    ret := (others => '0');
    preamble := get_preamble(NOC_FLIT_SIZE, large_flit);

    if preamble = PREAMBLE_HEADER or preamble = PREAMBLE_1FLIT then
      ret(MISC_NOC_FLIT_SIZE - 1 downto NEXT_ROUTING_WIDTH) :=
        large_flit(NOC_FLIT_SIZE - 1 downto NOC_FLIT_SIZE - MISC_NOC_FLIT_SIZE + NEXT_ROUTING_WIDTH);
      ret(NEXT_ROUTING_WIDTH - 1 downto 0) := large_flit(NEXT_ROUTING_WIDTH - 1 downto 0);
    else
      ret(MISC_NOC_FLIT_SIZE - 1 downto MISC_NOC_FLIT_SIZE - PREAMBLE_WIDTH) :=
        large_flit(NOC_FLIT_SIZE - 1 downto NOC_FLIT_SIZE - PREAMBLE_WIDTH);
      ret(MISC_NOC_FLIT_SIZE - PREAMBLE_WIDTH - 1 downto 0) :=
        large_flit(MISC_NOC_FLIT_SIZE - PREAMBLE_WIDTH - 1 downto 0);
    end if;

    return ret;
  end large_to_narrow_flit;

----------------------------------------------------------------------------------------
-- Remove the loops and use conditionals of local_x and local_y to find required ports
-- Same port generation must be used in tiles ports
-- This function will go to top and ROUTER_PORTS will be passed through parameter


  type ports_vec is array (TILES_NUM-1 downto 0) of std_logic_vector(4 downto 0);

  function set_router_ports(
    constant XLEN : integer;
    constant YLEN : integer)
    return ports_vec is
    variable ports : ports_vec;
  begin
    ports := (others => (others => '0'));
    --   0,0    - 0,1 - 0,2 - ... -    0,XLEN-1
    --    |        |     |     |          |
    --   1,0    - ...   ...   ... -    1,XLEN-1
    --    |        |     |     |          |
    --   ...    - ...   ...   ... -      ...
    --    |        |     |     |          |
    -- YLEN-1,0 - ...   ...   ... - YLEN-1,XLEN-1
    for i in 0 to YLEN-1 loop
      for j in 0 to XLEN-1 loop
        -- local ports are all set
        ports(i * XLEN + j)(4) := '1';
        if j /= XLEN-1 then
          -- east ports
          ports(i * XLEN + j)(3) := '1';
        end if;
        if j /= 0 then
          -- west ports
          ports(i * XLEN + j)(2) := '1';
        end if;
        if i /= YLEN-1 then
          -- south ports
          ports(i * XLEN + j)(1) := '1';
        end if;
        if i /= 0 then
          -- nord ports
          ports(i * XLEN + j)(0) := '1';
        end if;
      end loop;  -- j
    end loop;  -- i
    return ports;
  end set_router_ports;

  constant ROUTER_PORTS : ports_vec := set_router_ports(CFG_XLEN, CFG_YLEN);

end nocpackage;
