-- see: mail.md

local f = string.format

mail.registered_on_receives = {}
function mail.register_on_receive(func)
	mail.registered_on_receives[#mail.registered_on_receives + 1] = func
end

mail.receive_mail_message = "You have a new message from %s! Subject: %s\nTo view it, type /mail"
mail.read_later_message = "You can read your messages later by using the /mail command"

function mail.send(m)
	if type(m.from) ~= "string" then return false, "'from' is not a string" end
	if type(m.to) ~= "string" then return false, "'to' is not a string" end
	if type(m.body) ~= "string" then return false, "'body' is not a string" end

	-- defaults
	m.subject = m.subject or "(No subject)"

	-- limit subject line
	if string.len(m.subject) > 30 then
		m.subject = string.sub(m.subject,1,27) .. "..."
	end

	-- normalize to, cc and bcc while compiling a list of all recipients
	local recipients = {}
	local undeliverable = {}
	m.to = mail.concat_player_list(mail.extractMaillists(m.to, m.from))
	m.to = mail.normalize_players_and_add_recipients(m.to, recipients, undeliverable)
	if m.cc then
		m.cc = mail.concat_player_list(mail.extractMaillists(m.cc, m.from))
		m.cc = mail.normalize_players_and_add_recipients(m.cc, recipients, undeliverable)
	end
	if m.bcc then
		m.bcc = mail.concat_player_list(mail.extractMaillists(m.bcc, m.from))
		m.bcc = mail.normalize_players_and_add_recipients(m.bcc, recipients, undeliverable)
	end

	if next(undeliverable) then -- table is not empty
		local undeliverable_names = {}
		for name in pairs(undeliverable) do
			undeliverable_names[#undeliverable_names + 1] = '"' .. name .. '"'
		end
		return false, f("recipients %s don't exist; cannot send mail.", table.concat(undeliverable_names, ", "))
	end

	local extra = {}
	local extra_log
	if m.cc then
		table.insert(extra, "CC: " .. m.cc)
	end
	if m.bcc then
		table.insert(extra, "BCC: " .. m.bcc)
	end
	if #extra > 0 then
		extra_log = f(" (%s)", table.concat(extra, " - "))
	else
		extra_log = ""
	end

	minetest.log("action", f("[mail] %q send mail to %q%s with subject %q and body %q",
		m.from, m.to, extra_log, m.subject, m.body
	))

	local id
	if m.id then
		mail.delete_mail(m.from, m.id)
		id = m.id
	end

	-- form the actual mail
	local msg = {
		id = id or mail.new_uuid(),
		from = m.from,
		to = m.to,
		cc = m.cc,
		bcc = m.bcc,
		subject = m.subject,
		body = m.body,
		time = os.time(),
	}

	-- add in senders outbox
	local entry = mail.get_storage_entry(m.from)
	table.insert(entry.outbox, 1, msg)
	mail.set_storage_entry(m.from, entry)

	-- add in every receivers inbox
	for recipient in pairs(recipients) do
		entry = mail.get_storage_entry(recipient)
		table.insert(entry.inbox, msg)
		mail.set_storage_entry(recipient, entry)
	end

	-- notify recipients that happen to be online
	local mail_alert = f(mail.receive_mail_message, m.from, m.subject)
	for _, player in ipairs(minetest.get_connected_players()) do
		local name = player:get_player_name()
		if recipients[name] then
			minetest.chat_send_player(name, mail_alert)
		end
	end

	for i=1, #mail.registered_on_receives do
		if mail.registered_on_receives[i](m) then
			break
		end
	end

	return true
end

function mail.save_draft(m)
	if type(m.from) ~= "string" then return false, "'from' is not a string" end
	if type(m.to) ~= "string" then return false, "'to' is not a string" end
	if type(m.body) ~= "string" then return false, "'body' is not a string" end

	-- defaults
	m.subject = m.subject or "(No subject)"

	-- limit subject line
	if string.len(m.subject) > 30 then
		m.subject = string.sub(m.subject,1,27) .. "..."
	end

	minetest.log("verbose", f("[mail] %q saves draft with subject %q and body %q",
		m.from, m.subject, m.body
	))

	-- remove it is an update
	local id
	if m.id then
		mail.delete_mail(m.from, m.id)
		id = m.id
	end

	-- add (again ie. update) in sender drafts
	local entry = mail.get_storage_entry(m.from)
	table.insert(entry.drafts, 1, {
		id = id or mail.new_uuid(),
		from = m.from,
		to = m.to,
		cc = m.cc,
		bcc = m.bcc,
		subject = m.subject,
		body = m.body,
		time = os.time(),
	})
	mail.set_storage_entry(m.from, entry)

	return true

end
