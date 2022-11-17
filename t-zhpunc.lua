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

--[[ 结点跟踪工具
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
-- {
--     font={
--         [0x2018]={kern_l, kern_r, one_side_space, final_quad}, -- 左kern、右kern、单侧空（左右对齐用）、最终应用宽度（角，用于判断是否加空）
--         ...
--     },
--     ...
-- }
local puncs_font = {}

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
    [0x2014] = puncs_dash, -- — 半字线，兼puncs_full_junction

    -- 全角连接号
    [0xff5e] = puncs_full_junction, -- ～ 半字线

    -- 半角连接号
    [0x00b7] = puncs_half_junction, -- ·   MIDDLE DOT
    [0x002D] = puncs_half_junction, -- -   Hyphen-Minus. Will there be any side effects?
    [0x002F] = puncs_half_junction, -- /   Solidus
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

-- 处理每个标点前后的kern
local function process_punc (head, n)
    
    -- 取得结点字体的描述（未缩放的原始字模信息）
    local char = n.char
    local font = n.font

    -- 左右实际kern
    local l_kern
    local r_kern
    -- 单侧空白（两侧相同）
    local one_side_space
    -- 最终应用宽度
    local final_quad

    puncs_font[font] = puncs_font[font] or {}
    -- 空铅
    puncs_font[font]["quad"] = puncs_font[font]["quad"] or fontdata[font].parameters.quad -- 用结点宽度代替？？？
    local quad = puncs_font[font]["quad"]

    puncs_font[font][char] = puncs_font[font][char] or {}
    if  #puncs_font[font][char] >0 then -- 从表中取用
        l_kern =  puncs_font[font][char][1]
        r_kern =  puncs_font[font][char][2]
        one_side_space = puncs_font[font][char][3]
        final_quad = puncs_font[font][char][4]
    else -- 计算并缓存
        local desc = fontdata[font].descriptions[char]
        local desc_width = desc.width
        
        if not desc then return end --???
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
        
        local two_space -- 两侧总空
        -- if w_in < (desc_width * 0.45) then
            -- 实际宽度小于0.45角时，调整为0.5角/半字宽(使冒号为全角)
        if w_in < (desc_width * 0.5) then
            two_space = (desc_width / 2) - w_in
            final_quad = 0.5
        else
            -- 全角标点，整字宽
            two_space = desc_width - w_in
            final_quad = 1
        end
        -- 再居中
        l_kern = (two_space/2 - left_space) / desc_width * quad  --左kern比例
        puncs_font[font][char][1] = l_kern
        r_kern = (two_space/2 - right_space) / desc_width * quad --右kern比例
        puncs_font[font][char][2] = r_kern

        -- 左、右侧空白（供对齐行头、右侧收缩用）  TODO
        one_side_space = (two_space/2) / desc_width * quad
        puncs_font[font][char][3] = one_side_space

        -- 实际字宽（角）
        puncs_font[font][char][4] = final_quad
    end


    local prev = prev_punc(n)
    local next = next_punc(n)

    -- 实际占位半角的标点可能加空
    if  final_quad == 0.5
        and (Moduledata.zhpunc.model == quanjiao or  Moduledata.zhpunc.model == kaiming)
            then
        
        local space_table = inserting_space[ Moduledata.zhpunc.model]
        
        -- 后加空
        local next_space
        local next_space_table = space_table[puncs[n.char]]
        if next_space_table then
            if next then -- 后面是标点
                next_space = next_space_table[puncs[next.char]]
            elseif next == false then -- 是非标点可见结点（不是末尾nil）
                next_space = next_space_table[puncs_no]
            end
            if next_space then
                local space = node_new(glue_id)
                space.width = next_space * quad * Moduledata.zhpunc.space_quad
                head,_ = node_insertafter (head, n, space)
            end
        end
        
        -- 全角(前面无标点、不是行头时)前加空
        if  Moduledata.zhpunc.model == quanjiao then
            local pre_space
            if prev == false then
                pre_space = space_table[puncs_no][puncs[n.char]]
            end
            if pre_space then
                local space = node_new(glue_id)
                space.width = pre_space * quad * Moduledata.zhpunc.space_quad
                head,_ = node_insertbefore (head, n, space)
            end
        end
    end

    -- 尽可能调整为半字标点
    if  Moduledata.zhpunc.model ~= yuanyang then
        -- 插入kern
        local k
        head,k = node_insertbefore (head, n, nodes_pool_kern (l_kern))
        head,k = node_insertafter (head, n, nodes_pool_kern (r_kern))

        -- 更改系统插入右标点后、所有标点前的半字收缩胶 TODO 或更改scrp-cjk.lua
        if next or prev then
            local g = k.next
            while g do
                if g.id == glyph_id then
                    break
                elseif g.id == glue_id and g.shrink then
                    g.shrink = one_side_space
                    break
                end
                g = g.next
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
            -- 缓存、取用quad
            local font = n.font
            puncs_font[font] = puncs_font[font] or {}
            puncs_font[font]["quad"] = puncs_font[font]["quad"] or fontdata[font].parameters.quad -- 用结点宽度代替？？？
            local quad = puncs_font[font]["quad"]

            local list, p_class
            head, n, list, p_class = cut_punc_group(head,n)
            head, n = insert_list_before(head, n, list, p_class, quad)
        else
            n = n.next
        end
    end
    return head
end

-- 包装回调任务：分行前的过滤器
function Moduledata.zhpunc.my_linebreak_filter (head)
    head = compress_punc (head)
    if Moduledata.zhpunc.hangjian then
        head = raise_punc_to_hangjian(head)
    end
    return head, true
end

-- 分行后处理对齐
function Moduledata.zhpunc.align_left_puncs(head)
    local it = head
    while it do
        if it.id == hlist_id then
            -- show_detail(head,"处理行头标点前")
            local e = it.head
            local neg_kern = nil
            local hit = nil
            while e do
                if is_punc(e) then
                    if is_left_sign(e) then
                        hit = e
                    end
                    break
                end
                e = e.next
            end
            if hit ~= nil then
                -- 文本行整体向左偏移
                    -- local quad = quaddata[font]
                neg_kern = -puncs_font[hit.font][hit.char][3] --ah21
                -- neg_kern = -left_puncs[hit.char] * fontdata[hit.font].parameters.quad --ah21
                node_insertbefore(head, hit, nodes_pool_kern(neg_kern))
                -- 统计字符个数
                local w = 0
                local x = hit
                while x do
                    if is_punc(x) then w = w + 1 end
                    x = x.next
                end
                if w == 0 then w = 1 end
                -- 将 neg_kern 分摊出去
                x = it.head -- 重新遍历
                local av_neg_kern = -neg_kern/w
                local i = 0
                while x do
                    if is_punc(x) then
                        i = i + 1
                        -- 最后一个字符之后不插入 kern
                        if i < w then 
                            node_insertafter(head, x, nodes_pool_kern(av_neg_kern))
                        end
                    end
                    x = x.next
                end
            end
        end
        it = it.next

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
    nodes_tasks_appendaction("processors","after","Moduledata.zhpunc.my_linebreak_filter")
    -- 段落分行后回调
    nodes_tasks_appendaction("finalizers", "after", "Moduledata.zhpunc.align_left_puncs")
end

local function update_protrusions()
    -- 合并两表到新表myvector，而不是修改font-ext.lua中的vectors.quality
    -- TODO 补齐，使用实测数据并缓存
    -- 横排时    
    local my_vectors_quality = {
        [0x2018] = { 0.60, 0 },  -- ‘
        [0x2019] = { 0, 0.60 },  -- ’
        [0x201C] = { 0.50, 0 },  -- “
        [0x201D] = { 0, 0.35 },  -- ”
        [0x300C] = { 0.50, 0 }, -- 「
        [0x300E] = { 0.50, 0 }, -- 『
        [0x300A] = { 0.40, 0 },  -- 《
        [0x300B] = { 0, 0.60 },  -- 》
        [0x3009] = { 0, 0.60 }, -- 〉
        [0x3011] = { 0, 0.50 }, -- 】
        [0xFF08] = { 0.50, 0 },  -- （
        [0xFF09] = { 0, 0.60 },  -- ）
        [0x3001] = { 0, 0.65 },  -- 、
        [0xFF0c] = { 0, 0.65 },  -- ，
        [0x3002] = { 0, 0.60 },  -- 。
        [0xFF0E] = { 0, 0.50 },  -- ．
        [0xFF01] = { 0, 0.65 },   -- ！
        [0xFF1F] = { 0, 0.65 },  -- ？
        [0xFF1B] = { 0, 0.17 },   -- ；
        [0xFF1A] = { 0, 0.65 },   -- ：
    }
    -- 竖排时更新
    if Moduledata.vtypeset.appended then
        local puncs_to_rotated = {
            [0x3001] = {0, 0.65},   -- 、
            [0xFF0C] = {0, 0.5},   -- ，
            [0x3002] = {0, 0.6},   -- 。
            [0xFF0E] = {0, 0.6},   -- ．
            [0xFF1A] = {0, 0.3},   -- ：
            [0xFF01] = {0, 0.1},   -- ！
            [0xFF1B] = {0, 0.15},   -- ；
            [0xFF1F] = {0, 0.1},   -- ？
        }
        my_vectors_quality = table.merged (my_vectors_quality, puncs_to_rotated)
    end

    -- 挂载悬挂表、注册悬挂类
    local classes = fonts.protrusions.classes
    classes.myvector = {
        vector = 'myvector',
        factor = 1,
    }

    -- 标点悬挂/突出
    local vectors = fonts.protrusions.vectors
    vectors.myvector = table.merged (vectors.quality,my_vectors_quality)

    -- 扩展原有的字体特性default(后)为default(前)
    context.definefontfeature({"default"},{"default"},{mode="node",protrusion="myvector",liga="yes"})
    -- 在字体定义中应用或立即应用（ 注意脚本的引用时机; 只能一种字体？？ TODO）
    context.definedfont({"Serif*default"})

end
update_protrusions() --更新标点悬挂数据

return Moduledata.zhpunc


