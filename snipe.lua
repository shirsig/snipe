local version = '1.0'
local author = 'shirsig'

local PAGE_SIZE = 50

local auction_list_updated

snipe = {}

function snipe.on_load()
	snipe.log('Snipe v'..version..' loaded')
end

function snipe.on_event()
	if event == 'ADDON_LOADED' and string.lower(arg1) == 'snipe' then
		snipe.on_load()
	elseif event == 'AUCTION_HOUSE_SHOW' then
		snipe.on_auction_house_show()
	elseif event == 'AUCTION_HOUSE_CLOSED' then
		snipe.on_auction_house_closed()
	elseif event == 'AUCTION_ITEM_LIST_UPDATE' then
		auction_list_updated = true
	end
end

function snipe.on_update()
	if snipe.running and snipe.state and snipe.state.p() then
		return snipe.state.callback()
	end
end

function snipe.as_soon_as(p, callback)
	snipe.state = {
		p = p,
		callback = callback,
	}
end

function snipe.on_next_update(callback)
	snipe.state = {
		p = function() return true end,
		callback = callback,
	}
end

function snipe.on_auction_house_show()
	snipe.ready = true
	snipe.log('Snipe is ready.')
end

function snipe.on_auction_house_closed()
	if snipe.running then
		snipe.log('Snipe scan stopped.')
	end
	snipe.stop()
	snipe.ready = false
end

function snipe.log(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 1, 0)
	end
end

function snipe.format_money(val)
	local g = math.floor(val / 10000)	
	val = val - g * 10000	
	local s = math.floor(val / 100)	
	val = val - s * 100	
	local c = math.floor(val)
	
	local g_string = g ~= 0 and g .. 'g' or ''
	local s_string = s ~= 0 and s .. 's' or ''
	local c_string = (c ~= 0 or g == 0 and s == 0) and c .. 'c' or ''
			
	return g_string .. s_string .. c_string
end

function snipe.stop()
	snipe.running = false
end

function snipe.start()
	snipe.on_next_update(function()
		snipe.run()
	end)	
	snipe.running = true
end

function snipe.run(page)
	snipe.get_page(page, function()
		local auctions_on_page, total_auctions = GetNumAuctionItems('list')		
		snipe.process_page(auctions_on_page, function()
			local next_page = ceil(total_auctions / PAGE_SIZE) - 1	
			return snipe.run(next_page)	
		end)
	end)
end

function snipe.process_page(n, k)	
	return snipe.process_page_helper(1, n, k)
end

function snipe.process_page_helper(i, n, k)		
	if i <= n then
		return snipe.process_auction(i, function()
			return snipe.process_page_helper(i + 1, n, k)
		end)
	else 
		return k()
	end
end

function snipe.process_auction(i, k)
	local info = snipe.auction_info(i)

	if snipe.any(function(target) return snipe.match(target, info) end, snipe.targets) then
		snipe.purchase(info)
	end
	
	return k()
end

function snipe.get_page(page, k)
	snipe.as_soon_as(CanSendAuctionQuery, function()
		snipe.wait_for_page(k)
		QueryAuctionItems(
			nil,
			nil,
			nil,
			nil,
			nil,
			nil,
			page
		)
	end)
end

function snipe.match(target, auction)
	if GetMoney() < auction.buyout_price or auction.owner == UnitName('player') or auction.buyout_price == 0 then
		return false
	end
	
	local unit_price = auction.buyout_price / auction.count	
	local max_buyout = 10000 * (target.g or 0) + 100 * (target.s or 0) + (target.c or 0)

	return unit_price <= max_buyout and getn(target) > 0 and snipe.all(function(target_entry)
		return snipe.any(function(auction_entry) return string.upper(auction_entry) == string.upper(target_entry) end, auction)
	end, target)
end

function snipe.purchase(auction)
	PlaceAuctionBid('list', auction.page_index, auction.buyout_price)
end

function snipe.any(p, xs)
	local holds = false
	for _, x in ipairs(xs) do
		holds = holds or p(x)
	end
	return holds
end

function snipe.all(p, xs)
	local holds = true
	for _, x in ipairs(xs) do
		holds = holds and p(x)
	end
	return holds
end

function snipe.extract_tooltip(i)
	for j=1, 30 do
		getglobal('SNIPE_SCAN_TOOLTIPTextLeft'..j):SetText()
		getglobal('SNIPE_SCAN_TOOLTIPTextRight'..j):SetText()
	end
	SNIPE_SCAN_TOOLTIP:SetOwner(UIParent, 'ANCHOR_NONE')
	SNIPE_SCAN_TOOLTIP:SetAuctionItem('list', i)
	SNIPE_SCAN_TOOLTIP:Show()
	local tooltip = {}
	for j=1, 30 do
		local left_entry = getglobal('SNIPE_SCAN_TOOLTIPTextLeft'..j):GetText()
		if left_entry then
			tinsert(tooltip, left_entry)
		end
		local right_entry = getglobal('SNIPE_SCAN_TOOLTIPTextRight'..j):GetText()
		if right_entry then
			tinsert(tooltip, right_entry)
		end
	end
	return tooltip
end

function snipe.auction_info(i)
	local _, texture, count, quality, _, _, _, _, buyout_price, _, _, owner = GetAuctionItemInfo('list', i)
	
	local info = {
			owner = owner,
			page_index = i,			
			count = count,
			buyout_price = buyout_price,
			texture = texture,
			quality = quality,
	}

	local tooltip = snipe.extract_tooltip(i)
	
	for _, entry in ipairs(tooltip) do
		tinsert(info, entry)
	end

	return info
end

function snipe.wait_for_page(k)
	local t0 = time()
	auction_list_updated = false
	
	snipe.as_soon_as(function()
		if time() - t0 > 5 then -- we won't wait longer than 5 seconds
			return true
		end
		
		return auction_list_updated and snipe.owner_data_complete()
		
	end, k)
end

function snipe.owner_data_complete(k)
	local n, _ = GetNumAuctionItems('list')
	for i = 1, n do
		local auction_info = snipe.auction_info(i)
		if not auction_info.owner then
			return false
		end
	end
	return true
end

SLASH_SNIPE1 = '/snipe'
function SlashCmdList.SNIPE(parameter)
	if parameter == '' then
		if snipe.running then
			snipe.stop()
			snipe.log('Snipe scan stopped.')
		else
			snipe.log('Snipe is not running.')
		end
	elseif snipe.target_sets[parameter] then
		if not snipe.ready then
			snipe.log('Snipe is not ready.')
		else
			snipe.targets = snipe.target_sets[parameter]
			snipe.start()
			snipe.log('Snipe scan for target set "'..parameter..'" started.')
		end
	else
		snipe.log('No target set with name "'..parameter..'".')
	end
end