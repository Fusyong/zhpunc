Moduledata = Moduledata or {}
Moduledata.zhpunc = Moduledata.zhpunc or {}
-- 配合竖排
-- 竖排模块（判断是否挂载竖排，以便处理旋转的标点）
Moduledata.vtypeset = Moduledata.vtypeset or {}
Moduledata.vtypeset.appended = Moduledata.vtypeset.appended or false

-- 标点模式配置，默认全角
local quanjiao, kaiming, banjiao, yuanyang = "quanjiao", "kaiming", "banjiao","yuanyang"

local hlist_id   = nodes.nodecodes.hlist
local vlist_id   = nodes.nodecodes.vlist
local penalty_id   = nodes.nodecodes.penalty
local rule_id    = nodes.nodecodes.rule
local glyph_id   = nodes.nodecodes.glyph --node.id ('glyph')
local glue_id    = nodes.nodecodes.glue
local kern_id    = nodes.nodecodes.kern
local indentskip_id = nodes.subtypes.glue.indentskip

local fonthashes = fonts.hashes
local fontdata   = fonthashes.identifiers --字体身份表

local node_traverse = node.traverse
local node_tail = node.tail
local node_hpack = node.hpack
local node_insertbefore = node.insertbefore
local node_insertafter = node.insertafter
local nodes_pool_kern = nodes.pool.kern
local node_new = node.new
local node_copy = node.copy
local node_copylist = node.copylist
local node_remove = node.remove
local node_free = node.free
local nodes_tasks_appendaction = nodes.tasks.appendaction
local tex_sp = tex.sp

---[[ 结点跟踪工具
local function show_detail(n, label)
    local l = label or "======="
    print(">>>>>>>>>"..l.."<<<<<<<<<<")
    print(nodes.toutf(n))
    for i in node.traverse(n) do
        local char
        if i.id == glyph_id then
            char = utf8.char(i.char)
            print(i, char)
        elseif i.id == nodes.nodecodes.penalty then
            print(i, i.penalty)
        elseif i.id == nodes.nodecodes.glue then
            print(i, i.width, i.stretch, i.shrink, i.stretchorder, i.shrinkorder)
        elseif i.id == nodes.nodecodes.hlist then
            print(i, nodes.toutf(i.list),i.width,i.height,i.depth,i.shift,i.glue_set,i.glue_sign,i.glue_order)
        elseif i.id == nodes.nodecodes.kern then
            print(i, i.kern, i.expension)
        else
            print(i)
        end
    end
end
--]]


-- 标点缓存数据
-- {font=
--    {char={l_kern=, r_kern=, one_side_space=, final_quad=}},
--    {quad=}
-- }
Moduledata.zhpunc.puncs_font = {}

-- 标点分类
-- 语义单元前
local puncs_left_sign     = 'puncs_left_sign'     -- 左半标号，如《
-- 语义单元后
local puncs_right_sign    = 'puncs_right_sign'    -- 右半标号，如》
local puncs_inner_point   = 'puncs_inner_point'   -- 句内点号，如、
local puncs_ending_point  = 'puncs_ending_point'  -- 句末点号，如。
-- 语义单元中(视同)
local puncs_ellipsis      = 'puncs_ellipsis'      -- 省略号…
local puncs_dash          = 'puncs_dash'          -- 破折号—
-- 语义单元中
local puncs_full_junction = 'puncs_full_junction' -- 全角连接号～
local puncs_half_junction = 'puncs_half_junction' -- 半角连接号，如-
-- 非
local puncs_no            = 'puncs_no'          -- 非标点的可视结点

-- 加空的组合与数量
local inserting_space = {
    -- 开明
    [kaiming] = {
        [puncs_ending_point] =   {puncs_left_sign = 1,  --。《
                                  puncs_no        = 1}, --。囗
    },
    -- 全角
    [quanjiao] = {
        [puncs_no]           =   {puncs_left_sign = 1}, --囗《
        [puncs_right_sign]   =   {puncs_left_sign = 1,  --》《
                                  puncs_no        = 1}, --》囗
        [puncs_inner_point]  =   {puncs_left_sign = 1,  --、《
                                  puncs_no        = 1}, --、囗
        [puncs_ending_point] =   {puncs_left_sign = 1,  --。《
                                  puncs_no        = 1}, --。囗
    },
}

-- 所有标点
local puncs = {
    -- 左半标号
    [0x2018] = puncs_left_sign, -- ‘
    [0x201C] = puncs_left_sign, -- “
    [0x3008] = puncs_left_sign, -- 〈
    [0x300A] = puncs_left_sign, -- 《
    [0x3010] = puncs_left_sign, -- 【
    [0x3014] = puncs_left_sign, -- 〔
    [0xFF08] = puncs_left_sign, -- （
    [0xFF3B] = puncs_left_sign, -- ［
    -- ext
    [0x300C] = puncs_left_sign, -- 「
    [0x300E] = puncs_left_sign, -- 『
    [0x3016] = puncs_left_sign, -- 〖
    [0xFF5B] = puncs_left_sign, -- ｛

    -- 右半标号
    [0x2019] = puncs_right_sign, -- ’
    [0x201D] = puncs_right_sign, -- ”
    [0x3009] = puncs_right_sign, -- 〉
    [0x300B] = puncs_right_sign, -- 》
    [0x3011] = puncs_right_sign, -- 】
    [0x3015] = puncs_right_sign, -- 〕
    [0xFF09] = puncs_right_sign, -- ）
    [0xFF3D] = puncs_right_sign, -- ］
    -- ext
    [0x300D] = puncs_right_sign, -- 」
    [0x300F] = puncs_right_sign, -- 』
    [0x3017] = puncs_right_sign, -- 〗
    [0xFF5D] = puncs_right_sign, -- ｝

    -- 句内点号
    [0x3001] = puncs_inner_point,   -- 、
    [0xFF0C] = puncs_inner_point,   -- ，
    [0xFF1A] = puncs_inner_point,   -- ：
    [0xFF1B] = puncs_inner_point,   -- ；

    -- 句末点号
    [0xFF01] = puncs_ending_point,   -- ！
    [0xFF1F] = puncs_ending_point,   -- ？
    [0x3002] = puncs_ending_point,   -- 。
    -- ext
    [0xFF0E] = puncs_ending_point,   -- ．

    -- 省略号
    [0x2026] = puncs_ellipsis, -- …

    -- 破折号
    [0x2014] = puncs_dash, -- — 一字线，兼puncs_full_junction

    -- 全角连接号
    [0xff5e] = puncs_full_junction, -- ～ 一字线

    -- 半角连接号
    [0x00b7] = puncs_half_junction, -- ·   MIDDLE DOT
    -- 不处理半角字符
    -- [0x002D] = puncs_half_junction, -- -   Hyphen-Minus. Will there be any side effects?
    -- [0x002F] = puncs_half_junction, -- /   Solidus
    -- ext
    [0xff0f] = puncs_half_junction, -- ／   Solidus
}

-- 竖排时要旋转的标点/竖排标点（装在hlist中）
local puncs_to_rotate = {
    [0x3001] = true,   -- 、
    [0xFF0C] = true,   -- ，
    [0x3002] = true,   -- 。
    [0xFF0E] = true,   -- ．
    [0xFF1A] = true,   -- ：
    -- 以下，后两位压缩值与前两位相乘后相等，即与竖排模块的“居中”一致
    [0xFF01] = true,   -- ！
    [0xFF1B] = true,   -- ；
    [0xFF1F] = true,   -- ？
}

-- 行间符号
local puncs_to_hangjian = {
    [0x3001] = true,   -- 、
    [0xFF0C] = true,   -- ，
    [0x3002] = true,   -- 。
    [0xFF0E] = true,   -- ．
    [0xFF1A] = true,   -- ：

    [0xFF01] = true,   -- ！
    [0xFF1B] = true,   -- ；
    [0xFF1F] = true,   -- ？

    -- [0x2018] = true,  -- ‘
    -- [0x2019] = true,  -- ’
    -- [0x201C] = true,  -- “
    -- [0x201D] = true,  -- ”
}

-- 全角标点
local full_quad_puncs = {
    [0x2026] = true, -- …
    [0x2014] = true, -- — 半字线，兼puncs_full_junction
    [0xff5e] = true, -- ～ 半字线
    [0xff0f] = true, -- ／   Solidus
}
-- 竖排全角标点
local v_full_quad_puncs = {
    [0xFF01] = true,   -- ！
    [0xFF1B] = true,   -- ；
    [0xFF1F] = true,   -- ？
}

-- 是标点结点
-- @n: glyph | hlist
-- @return: false | 1 | 2 （不是标点 | 一般标点 | 将要旋转的标点）
local function is_punc(n)
    if n.id == glyph_id then
        -- 竖排旋转标点
        if Moduledata.vtypeset.appended and puncs_to_rotate[n.char] then
            return 2
        elseif puncs[n.char] then
            return 1
        else
            return false
        end
    else
        return false
    end
end

-- 是全角标点结点
-- @n: glyph | hlist
-- @return: boolean
local function is_full_quad_punc(n)
    if n.id == glyph_id then
        local char = n.char
        if full_quad_puncs[char] then
            return true
        elseif Moduledata.vtypeset.appended and v_full_quad_puncs[char] then
            return true
        elseif is_punc(n) then
            return false
        end
    end
end

-- 是左标号
local function is_left_sign(n)
    if puncs[n.char] == puncs_left_sign then
        return true
    else
        return false
    end
end

-- 是右标号
local function is_right_sign(n)
    local p_class = puncs[n.char]
    if p_class == puncs_right_sign
    or p_class == puncs_inner_point
    or p_class == puncs_ending_point
    then
        return true
    else
        return false
    end
end

-- 同组末尾结点

local function is_visible_node(n)
    local ids = {
        [hlist_id] = true,
        [vlist_id] = true,
        [rule_id ] = true,
        [glyph_id] = true,
    }
    if ids[n.id] then --  and n.width > 0且有实际宽度（必要吗？？？）
        return true
    else
        return false
    end
end

-- 后一个可见节点是标点
local function next_punc(n)
    local next_n = n.next
    while next_n do
        if is_visible_node(next_n) then
            if is_punc(next_n) then
                return next_n
            else
                return false
            end
        end
        next_n = next_n.next
    end
    return nil -- n顶头
end

-- 前一个可见节点是标点
local function prev_punc(n)
    local prev_n = n.prev
    while prev_n do
        if is_visible_node(prev_n) then
            if is_punc(prev_n) then
                return prev_n
            else
                return false
            end
        end
        prev_n = prev_n.prev
    end
    return nil --n顶头
end

-- 标点类别，-1：左；0：中；1：右
local function punc_class(n)
    if is_left_sign(n) then
        return  -1
    elseif is_right_sign(n) then
        return 1
    else
        return 0
    end
end

local function node_remove_list(head, n, m)
    local to_freed
    while n and n ~= m do
        if to_freed then
            node_free(to_freed)
        end
        to_freed = n
        head,n = node_remove(head, n)
    end
    return head, n
end

-- 剪切从某个起始的同类标点（左标点、右标点、其余/中标点）组
local function cut_punc_group(head, n)
    local begin = n
    local p_class = punc_class(n)
    local the_end = n.next
    n = next_punc(n)
    while n do
        if puncs_to_hangjian[n.char] and p_class == punc_class(n) then
            the_end = n.next
            n = next_punc(n)
        else
            break
        end
    end

    -- 覆盖前后的kern TODO 更可靠的逻辑
    local pre = begin.prev
    if pre and pre.id == kern_id then
        begin = pre
    end
    -- 取消前置胶的弹性 TODO 更可靠的逻辑
    pre = begin.prev
    if pre and pre.id == glue_id then
        pre.stretch = 0
        pre.shrink = 0
    end
    if the_end and the_end.id == kern_id then
        the_end = the_end.next
    end
    local copyed_list = node_copylist(begin, the_end)
    local current
    head, current = node_remove_list(head, begin, the_end)
    return head, current, copyed_list, p_class
end

-- 以hlist形式插入列表
local function insert_list_before(head, current, list, p_class,quad)
    -- local l = node_new(hlist_id)
    -- l.head = list

    -- 模拟\hss，插入列表首尾
    local hss = node_new(glue_id)
    hss.stretch = 65536
    hss.stretchorder = 2
    hss.shrink = 65536
    hss.shrinkorder = 2
    hss.width = 0
    if p_class == 1 then
        list,_ = node_insertbefore(list, list, hss)
    elseif p_class == -1 then
        list,_ = node_insertafter(list, node_tail(list), hss)
    end

    -- 把列表装入0宽度的盒子中
    local box, _ = node_hpack(list,0,"exactly")
    box.shift = -quad * 0.4

    head, current = node_insertbefore(head,current, box)

    return head, current
end


-- 计算、缓存并返回标点数据
function Moduledata.zhpunc.punc_data(n)

    local char = n.char
    local font = n.font

    -- 左右实际kern
    local l_kern
    local r_kern
    -- 单侧空白（两侧相同）
    local one_side_space
    -- 最终应用宽度
    local final_quad

    Moduledata.zhpunc.puncs_font[font] = Moduledata.zhpunc.puncs_font[font] or {}

    -- 空铅
    Moduledata.zhpunc.puncs_font[font]["quad"] = Moduledata.zhpunc.puncs_font[font]["quad"] or fontdata[font].parameters.quad
    -- 英文字体quad多变，稳定的是fontdata[font].parameters.units-- em的单元数，通常是1000
    local quad = Moduledata.zhpunc.puncs_font[font]["quad"]

    Moduledata.zhpunc.puncs_font[font][char] = Moduledata.zhpunc.puncs_font[font][char] or {}

    if  #Moduledata.zhpunc.puncs_font[font][char] < 1 then
        local desc = fontdata[font].descriptions[char]
        local desc_width = desc.width -- 外框宽度
        
        -- if not desc then return end --???
        local boundingbox = desc.boundingbox
        local x1 =  boundingbox[1]
        local x2 =  boundingbox[3]
        
        local w_in --内框宽度
        local left_space --前空
        local right_space -- 后空
        if is_punc(n) == 1 then -- 一般标点
            left_space = x1
            right_space = desc_width - x2
            w_in = x2 - x1
        elseif is_punc(n) == 2 then --旋转的标点
            left_space = x1
            -- 有些字体可能没有深度（整体在线上时）、高度（整体在线下时）数据
            local desc_depth = desc.depth or -desc.boundingbox[2]
            right_space = desc_width - left_space - desc_depth - desc.height
            w_in =  desc_depth + desc.height
        end
        Moduledata.zhpunc.puncs_font[font][char]["left_space"] = left_space / desc_width * quad
        Moduledata.zhpunc.puncs_font[font][char]["right_space"] = right_space / desc_width * quad
        
        local two_space -- 两侧总空
        if is_full_quad_punc(n) then
            -- 全角标点，整字宽
            two_space = desc_width - w_in
            final_quad = 1
        else
            -- 半角标点
            two_space = (desc_width / 2) - w_in
            final_quad = 0.5
        end
        -- 再居中
        l_kern = (two_space/2 - left_space) / desc_width * quad  --左kern
        Moduledata.zhpunc.puncs_font[font][char]["l_kern"] = l_kern
        r_kern = (two_space/2 - right_space) / desc_width * quad --右kern
        Moduledata.zhpunc.puncs_font[font][char]["r_kern"] = r_kern

        -- 左、右侧空白（供对齐行头、右侧收缩用）  TODO
        one_side_space = (two_space/2)  / desc_width * quad
        Moduledata.zhpunc.puncs_font[font][char]["one_side_space"] = one_side_space

        -- 实际字宽（角）
        Moduledata.zhpunc.puncs_font[font][char]["final_quad"] = final_quad

    end
    return Moduledata.zhpunc.puncs_font[font][char]
end

-- 处理每个标点前后的kern和胶
local function process_punc (head, n)

    local p_data, l_kern, r_kern, one_side_space, final_quad, quad
    p_data = Moduledata.zhpunc.punc_data(n)
    if p_data then
        l_kern = p_data["l_kern"]
        r_kern = p_data["r_kern"]
        one_side_space = p_data["one_side_space"]
        final_quad = p_data["final_quad"]
    end
    quad = Moduledata.zhpunc.puncs_font[n.font]["quad"]

    local prev_p = prev_punc(n)
    local next_p = next_punc(n)
    
    -- 实际占位半角的标点可能加空
    if  final_quad == 0.5
    and (Moduledata.zhpunc.model == quanjiao or  Moduledata.zhpunc.model == kaiming) then
        
        local space_table = inserting_space[ Moduledata.zhpunc.model]
        
        -- 后加空
        local char = n.char
        local next_space
        local next_space_table = space_table[puncs[char]]
        if next_space_table then
            if next_p then -- 后面是标点
                next_space = next_space_table[puncs[next_p.char]]
            elseif next_p == false then -- 是非标点可见结点（不是末尾nil）
                next_space = next_space_table[puncs_no]
            end
            if next_space then
                local space = node_new(glue_id)
                space.width = next_space * quad * Moduledata.zhpunc.space_quad
                head,_ = node_insertafter (head, n, space)
                -- TODO 加罚点和半空压缩胶水
            end
        end
        
        -- 全角(前面无标点、不是行头时)前加空
        if  Moduledata.zhpunc.model == quanjiao then
            local pre_space
            if prev_p == false then
                pre_space = space_table[puncs_no][puncs[char]]
            end
            if pre_space then
                local space = node_new(glue_id)
                space.width = pre_space * quad * Moduledata.zhpunc.space_quad
                head,_ = node_insertbefore (head, n, space)
                -- TODO 加罚点和半空压缩胶水
            end
        end
    end

    -- 尽可能调整为半字标点
    if  Moduledata.zhpunc.model ~= yuanyang then

        -- 寻找hanzi脚本注入的前、后的收缩胶
        local function the_shrink_glue(current_n, dir)
            while current_n do

                if dir == "next" then
                    current_n = current_n.next
                end
                if dir == "prev" then
                    current_n = current_n.prev
                end

                if current_n then
                    if not (current_n.id == glue_id or current_n.id == penalty_id) then
                        break
                    else
                        if current_n.id == glue_id and current_n.shrink > 0 then
                            return current_n
                        end
                    end
                else
                    break
                end
            end
        end

        -- 插入kern、更改收缩胶 TODO 可能改到属于左右字符的收缩胶，应更健壮
        local k
        local shinnk_glue
        head,k = node_insertbefore (head, n, nodes_pool_kern (l_kern))
        shinnk_glue = the_shrink_glue(k, "prev")
        if shinnk_glue then --前面的收缩，考虑前面是标点的情况
            local shrink = one_side_space
            if prev_p then
                shrink = one_side_space + Moduledata.zhpunc.punc_data(prev_p)["one_side_space"]
            end
            shinnk_glue.shrink = shrink
        end
        
        head,k = node_insertafter (head, n, nodes_pool_kern (r_kern))
        if  not next_p then --仅处理后面不是标时
            shinnk_glue = the_shrink_glue(k, "next")
            if shinnk_glue then
                shinnk_glue.shrink = one_side_space
            end
        end
    end

    return head

end

-- 压缩标点
local function compress_punc (head)
    for n in node_traverse(head) do
        if is_punc(n) then
            head = process_punc (head, n)
        end
    end
    return head
end

-- 实现行间标点
local function raise_punc_to_hangjian(head)
    local n = head
    while n do
        if puncs_to_hangjian[n.char] then
            Moduledata.zhpunc.punc_data(n) --更新标点数据
            local font = n.font
            local quad = Moduledata.zhpunc.puncs_font[font]["quad"]

            local list, p_class
            head, n, list, p_class = cut_punc_group(head,n)
            head, n = insert_list_before(head, n, list, p_class, quad)
        else
            n = n.next
        end
    end
    return head
end

-- 分行前的标点处理：压缩与加空；行间
function Moduledata.zhpunc.process_puncs(head)
    -- show_detail(head,"1before")
    head = compress_punc (head)
    if Moduledata.zhpunc.hangjian then
        head = raise_punc_to_hangjian(head)
    end
    -- show_detail(head,"1after")
    return head, true
end

-- 两端凸排
function Moduledata.zhpunc.protrude(head)
    -- show_detail(head,"before")
    -- 左侧
    local head_p = next_punc(head)
    if head_p and is_left_sign(head_p) then
        local n_data = Moduledata.zhpunc.punc_data(head_p)
        local left_space = n_data["left_space"]
        local kern = node_new(kern_id, "leftmarginkern")
        kern.kern = -left_space
        head, kern = node_insertbefore(head, head_p, kern)
        -- 取消原有的kern
        local prev_n = kern.prev
        if prev_n.id == kern_id then
            prev_n.kern = 0
        end
    end
    
    -- 右侧
    local tail_p = prev_punc(node_tail(head))
    if tail_p and is_right_sign(tail_p) then
        local n_data = Moduledata.zhpunc.punc_data(tail_p)
        local right_space = n_data["right_space"]
        -- local right_space = -puncs_font[n.font][n.char]["one_side_space"] --ah21
        local kern = node_new(kern_id, "rightmarginkern")
        kern.kern = -right_space
        head, kern = node_insertafter(head, tail_p, kern)
        -- 取消原有的kern
        local next_n = kern.next
        if next_n.id == kern_id then
            next_n.kern = 0
        end
    end
    
    -- show_detail(head,"after")
    return head
end


-- 仅处理段落列表
function Moduledata.zhpunc.protrude_main(head)
    local n = head
    while n do
        if n.id == hlist_id then
            local copy_list = node_copylist(n.head)
            -- 更改后再次包装为相同长度的vlist，即可重设胶性
            local new_n = node_hpack( Moduledata.zhpunc.protrude(copy_list),n.width, "exactly")
            head, new_n = node_insertbefore(head, n, new_n)
            head, n = node_remove(head, n, true)
        else
            n = n.next
        end
    end
    return head, done
end

-- 传参设置
function Moduledata.zhpunc.set(pattern, spacequad, hangjian)
    Moduledata.zhpunc.model = pattern
    if hangjian == "false" then
        hangjian = false
    elseif hangjian == "true" then
        hangjian = true
    else
        hangjian = false
    end
    Moduledata.zhpunc.hangjian = hangjian
    Moduledata.zhpunc.space_quad = spacequad
end

-- 挂载/启动任务
function Moduledata.zhpunc.append()
    -- 预处理后（段落分行前）回调
    nodes_tasks_appendaction("processors","after","Moduledata.zhpunc.process_puncs")
    -- 段落分行后回调
    -- nodes_tasks_appendaction("finalizers", "after", "Moduledata.zhpunc.align_left_puncs")
    nodes_tasks_appendaction("finalizers", "after", "Moduledata.zhpunc.protrude_main")
end

return Moduledata.zhpunc


