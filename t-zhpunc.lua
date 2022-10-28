Moduledata = Moduledata or {}
Moduledata.zhpunc = Moduledata.zhpunc or {}
-- 配合直排
Moduledata.vertical_typeset = Moduledata.vertical_typeset or {}
Moduledata.vertical_typeset.appended = Moduledata.vertical_typeset.appended or false

-- 直排模块（判断是否挂载直排，以便处理旋转的标点）
Moduledata.vertical_typeset = Moduledata.vertical_typeset or {}

-- 标点模式配置，默认全角
local quanjiao, kaiming, banjiao, yuanyang, hangjian = "quanjiao", "kaiming", "banjiao","yuanyang","hangjian"
Moduledata.zhpunc.model = Moduledata.zhpunc.model or quanjiao
-- 
-- 临时设置 TODO 用户接口
-- 
-- Moduledata.zhpunc.model = hangjian -- TODO
Moduledata.zhpunc.model = yuanyang
Moduledata.zhpunc.model = banjiao
Moduledata.zhpunc.model = quanjiao
Moduledata.zhpunc.model = kaiming
local model = Moduledata.zhpunc.model

-- 一个加空的宽度（默认0.5角）
Moduledata.zhpunc.space_factor = Moduledata.zhpunc.space_factor or 0.5
-- Moduledata.zhpunc.space_factor = 0.2
local space_factor = Moduledata.zhpunc.space_factor

local hlist_id   = nodes.nodecodes.hlist
local vlist_id   = nodes.nodecodes.vlist
local rule_id    = nodes.nodecodes.rule
local glyph_id   = nodes.nodecodes.glyph --node.id ('glyph')
local glue_id    = nodes.nodecodes.glue

local fonthashes = fonts.hashes
local fontdata   = fonthashes.identifiers --字体身份表

local node_traverse = node.traverse
local node_insertbefore = node.insertbefore
local node_insertafter = node.insertafter
local nodes_pool_kern = nodes.pool.kern
local node_new = node.new
local node_copy = node.copy
local node_remove = node.remove
local nodes_tasks_appendaction = nodes.tasks.appendaction
local tex_sp = tex.sp

---[[ 结点跟踪工具
local function show_detail(n, label) 
    print(">>>>>>>>>"..label.."<<<<<<<<<<")
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
            print(i, nodes.toutf(i.list))
        else
            print(i)
        end
    end
end
--]]


-- 标点缓存数据
-- {
--     font={
--         [0x2018]={kern_l, kern_r, s_l}, -- 左kern、右kern、左空（左对齐启用）
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

-- 加空配置的数量
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
    [0x3002] = true,   -- 。
    [0xFF0C] = true,   -- ，
    [0xFF0E] = true,   -- ．
    [0xFF1A] = true,   -- ：
    -- 以下，后两位压缩值与前两位相乘后相等，即与直排模块的“居中”一致
    [0xFF01] = true,   -- ！
    [0xFF1B] = true,   -- ；
    [0xFF1F] = true,   -- ？
}

-- 是标点结点
-- @n: glyph | hlist
-- @return: false | 1 | 2 （不是标点 | 一般标点 | 将要旋转的标点）
local function is_punc(n)
    if n.id == glyph_id then
        -- 直排旋转标点
        if Moduledata.vertical_typeset.appended and puncs_to_rotate[n.char] then
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

    puncs_font[font] = puncs_font[font] or {}
    -- 空铅
    puncs_font[font]["quad"] = puncs_font[font]["quad"] or fontdata[font].parameters.quad -- 用结点宽度代替？？？
    local quad = puncs_font[font]["quad"]

    puncs_font[font][char] = puncs_font[font][char] or {}
    if  #puncs_font[font][char] >0 then -- 从表中取用
        l_kern =  puncs_font[font][char][1]
        r_kern =  puncs_font[font][char][2]
        one_side_space = puncs_font[font][char][3]
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
        if w_in < (desc_width / 2) then
            -- 半角标点，半字宽
            two_space = (desc_width / 2) - w_in
        else
            -- 全角标点，整字宽
            two_space = desc_width - w_in
        end
        -- 再居中
        l_kern = (two_space/2 - left_space) / desc_width * quad  --左kern比例
        puncs_font[font][char][1] = l_kern
        r_kern = (two_space/2 - right_space) / desc_width * quad --右kern比例
        puncs_font[font][char][2] = r_kern

        -- 左、右侧空白（供对齐行头、右侧收缩用）  TODO
        one_side_space = (two_space/2) / desc_width * quad
        puncs_font[font][char][3] = one_side_space
    end


    local prev = prev_punc(n)
    local next = next_punc(n)

    -- 加空
    if model == quanjiao or model == kaiming then
        
        local space_table = inserting_space[model]
        
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
                space.width = next_space * quad * space_factor
                head,_ = node_insertafter (head, n, space)
            end
        end
        
        -- 全角(前面无标点、不是行头时)前加空
        if model == quanjiao then
            local pre_space
            if prev == false then
                pre_space = space_table[puncs_no][puncs[n.char]]
            end
            if pre_space then
                local space = node_new(glue_id)
                space.width = pre_space * quad * space_factor
                head,_ = node_insertbefore (head, n, space)
            end
        end
    end

    -- 尽可能调整为半字标点
    if model ~= yuanyang then
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

    if model == hangjian then
        -- TODO 同组标点整体提升、对齐
        local l = node_new("hlist")
        local w = n.width
        l.width = 0
        l.list =  node_copy(n) --复制结点到新建的结点列表\hbox下
        -- 替换原结点
        head, l = node_insertafter(head, n, l)
        head, l = node_remove(head, n) -- 删除销毁结点会出错

    end

    return head

end

-- 迭代段落结点列表，处理标点组
local function compress_punc (head)
    for n in node_traverse(head) do
        if is_punc(n) then
            head = process_punc (head, n)
        end
    end
    return head
end


-- 包装回调任务：分行前的过滤器
function Moduledata.zhpunc.my_linebreak_filter (head)
    head = compress_punc (head)
    return head, true
end

-- 分行后处理对齐
function Moduledata.zhpunc.align_left_puncs(head)
    local it = head
    while it do
        if it.id == hlist_id then
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
    -- print(":::分摊行头压缩后nodes.tosequence(head):::")
    -- print(nodes.tosequence(head))
    return head, done
end

-- 挂载任务
function Moduledata.zhpunc.opt ()
    -- 段落分行前回调（最后调用）
    nodes_tasks_appendaction("processors","after","Moduledata.zhpunc.my_linebreak_filter")
    -- 段落分行后回调（最后调用）
    nodes_tasks_appendaction("finalizers", "after", "Moduledata.zhpunc.align_left_puncs")
end



local function update_protrusions()

    -- 标点悬挂/突出
    local classes = fonts.protrusions.classes
    local vectors = fonts.protrusions.vectors
    -- 挂载悬挂表、注册悬挂类
    classes.myvector = {
    vector = 'myvector',
    factor = 1,
    }
    
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
    -- 直排时更新
    if Moduledata.vertical_typeset.appended then
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
    
    vectors.myvector = table.merged (vectors.quality,my_vectors_quality)
    
    -- 扩展原有的字体特性default(后)为default(前)
    context.definefontfeature({"default"},{"default"},{mode="node",protrusion="myvector",liga="yes"})
    -- 在字体定义中应用或立即应用（ 注意脚本的引用时机; 只能一种字体？？ TODO）
    context.definedfont({"Serif*default"})
    --[[
    % 扩展原有的字体特性default(后)为default(前)
    \definefontfeature[default][default][mode=node,protrusion=myvector,liga=yes]
    % 或立即应用（只能一种字体？？注意脚本的引用时机）
    \definedfont[Serif*default]
    --]]

end
update_protrusions() --更新标点悬挂数据

return Moduledata.zhpunc


