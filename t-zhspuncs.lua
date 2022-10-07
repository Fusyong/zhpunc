Moduledata = Moduledata or {}
Moduledata.zhspuncs = Moduledata.zhspuncs or {}
-- 配合直排
Moduledata.vertical_typeset = Moduledata.vertical_typeset or {}
Moduledata.vertical_typeset.appended = Moduledata.vertical_typeset.appended or false

-- 直排模块（判断是否挂载直排，以便处理旋转的标点）
Moduledata.vertical_typeset = Moduledata.vertical_typeset or {}


local hlist = nodes.nodecodes.hlist
local glyph_id   = nodes.nodecodes.glyph --node.id ('glyph')
local glue_id   = nodes.nodecodes.glue

local fonthashes = fonts.hashes
local fontdata   = fonthashes.identifiers --字体身份表

local node_traverse = node.traverse
local node_insertbefore = node.insertbefore
local node_insertafter = node.insertafter
local nodes_pool_kern = nodes.pool.kern
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

-- TODO：
-- 调整为c-p-c、c-p--p-c六种数据（目前缺cp--pc两种）；
-- 再左、右、中标点分组

-- 标点缓存数据
-- {
--     font={
--         [0x2018]={kern_l, kern_r, s_l}, -- 左kern、右kern、左空（左对齐启用）
--         ...
--     },
--     ...
-- }
local puncs_font = {}

-- 左半标点
local puncs_left = {
    [0x2018] = true, -- ‘
    [0x201C] = true, -- “
    [0x3008] = true, -- 〈
    [0x300A] = true, -- 《
    [0x300C] = true, -- 「
    [0x300E] = true, -- 『
    [0x3010] = true, -- 【
    [0x3014] = true, -- 〔
    [0x3016] = true, -- 〖
    [0xFF08] = true, -- （
    [0xFF3B] = true, -- ［
    [0xFF5B] = true, -- ｛
}

-- 右标点
local puncs_right = {
    -- 右半标点
    [0x2019] = true, -- ’
    [0x201D] = true, -- ”
    [0x3009] = true, -- 〉
    [0x300B] = true, -- 》
    [0x300D] = true, -- 」
    [0x300F] = true, -- 』
    [0x3011] = true, -- 】
    [0x3015] = true, -- 〕
    [0x3017] = true, -- 〗
    [0xFF09] = true, -- ）
    [0xFF3D] = true, -- ］
    [0xFF5D] = true, -- ｝
    -- 单右标点
    [0x3001] = true,   -- 、
    [0x3002] = true,   -- 。
    [0xFF0C] = true,   -- ，
    [0xFF0E] = true,   -- ．
    [0xFF1A] = true,   -- ：
    [0xFF1B] = true,   -- ；
    [0xFF01] = true,   -- ！
    [0xFF1F] = true,   -- ？
    [0xFF05] = true,    -- ％
    [0x2500] = true,    -- ─
    -- 双用左右皆可，单用仅在文右
    [0x2014] = true, -- — 半字线
    [0x2026] = true, -- …
}

-- 所有标点
local puncs = table.merged(puncs_left, puncs_right)

-- 旋转过的标点/竖排标点（装在hlist中）
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

-- 是标点结点(false, 一般:1, 将要旋转:2)
-- @glyph | hlist n 结点
-- @return false | 1 | 2
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

-- 是左标点
local function is_left_punc(n)
    if puncs_left[n.char] then
        return true
    else
        return false
    end
end

-- 后一个字符节点是标点
local function next_is_punc(n)
    local next_n = n.next
    while next_n do
        if next_n.id == glyph_id then
            if is_punc(next_n) then
                return true
            else
                return false
            end
        end
        next_n = next_n.next
    end
end

-- 前一个字符节点是标点
local function prev_is_punc(n)
    local prev_n = n.prev
    while prev_n do
        if prev_n.id == glyph_id then
            if is_punc(prev_n) then
                return true
            else
                return false
            end
        end
        prev_n = prev_n.prev
    end
end

-- 本结点与前后是不是标点：false，only，with_pre， with_next，all
local function is_zhcnpunc_node_group (n)
    local prev = prev_is_punc(n)
    local current = is_punc(n)
    local next = next_is_punc(n)
    if current then
        if next and prev then
            return "all_three"
        elseif next then
            return "with_next"
        elseif prev then
            return "with_prev"
        else
            return "only_me"
        end
    else
        return false
    end
end

-- 处理每个标点前后的kern
local function process_punc (head, n, punc_flag)
    
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
    if  #puncs_font[font][char] >0 then
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
    
    
    local left_kern, right_kern = 0.0, 0.0
    if punc_flag == "only_me" then
        left_kern = 0 --c-pc
        right_kern = 0 --cp-c
    elseif punc_flag == "with_next" then
        left_kern = 0 --c-ppc
        right_kern = r_kern --cp-pc
    elseif punc_flag == "with_prev" then
        left_kern = l_kern --c-ppc
        right_kern = 0 --cp-pc
    elseif punc_flag == "all_three" then
        left_kern = l_kern --c-ppc
        right_kern =r_kern --cp-pc
    end

    -- 插入kern
    local k
    head,k = node_insertbefore (head, n, nodes_pool_kern (left_kern))
    head,k = node_insertafter (head, n, nodes_pool_kern (right_kern))

    -- 更改系统插入右标点后、所有标点前的半字收缩胶 TODO 可以更改系统常量吗？？？
    if punc_flag == "with_next" or punc_flag == "all_three" then
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

-- 迭代段落结点列表，处理标点组
local function compress_punc (head)
    for n in node_traverse(head) do
        -- if is_punc(n) then
            local n_flag = is_zhcnpunc_node_group (n)
            -- 至少本结点是标点
            if n_flag then
                process_punc (head, n, n_flag)
            end
        -- end
    end
end



-- 包装回调任务：分行前的过滤器
function Moduledata.zhspuncs.my_linebreak_filter (head)
    compress_punc (head)
    return head, true
end

-- 分行后处理对齐
function Moduledata.zhspuncs.align_left_puncs(head)
    local it = head
    while it do
        if it.id == hlist then
            local e = it.head
            local neg_kern = nil
            local hit = nil
            while e do
                if is_punc(e) then
                    if is_left_punc(e) then
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
function Moduledata.zhspuncs.opt ()
    -- 段落分行前回调（最后调用）
    nodes_tasks_appendaction("processors","after","Moduledata.zhspuncs.my_linebreak_filter")
    -- 段落分行后回调（最后调用）
    nodes_tasks_appendaction("finalizers", "after", "Moduledata.zhspuncs.align_left_puncs")
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

return Moduledata.zhspuncs


