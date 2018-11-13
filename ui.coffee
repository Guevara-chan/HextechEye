# ~League of Legends pick advisor.
# ==Extnesion methods==
Function::getter = (name, proc)	-> Reflect.defineProperty @prototype, name, {get: proc, configurable: true}
Function::setter = (name, proc)	-> Reflect.defineProperty @prototype, name, {set: proc, configurable: true}
Map::bump	= (key, step = 1) -> @set key, (if (val = @get key)? then val + step else 1)

#.{ [Classes]
class Stat
	cache_key	= "HextechEye_cache[0.02]"
	stamp_key	= cache_key + ":date"

	# --Methods goes here.
	constructor: () ->
		@ready = if @reload() then new Promise((resolve) -> resolve()) else @load()

	url2doc: (path) ->
		fetch("#{if process?.type then '' else 'https://cors.io/?'}http://www.leagueofgraphs.com" + path)
		.then (resp) -> resp.text()
		.then (html) -> (new DOMParser).parseFromString(html, "text/html")#.documentElement

	load: () ->
		@url2doc("/ru/champions/counters").then ((doc) -> # Getting page itself to parse.
			# Preinit.
			@champions = new Map
			# Main parsing loop.
			rows = doc.querySelector(".data_table").querySelectorAll("tr")				 # Extarcting all table rows.
			await Promise.all (for entry in rows when entry = entry.querySelector "td"	 # Parsing all non-empty entris.
				@champions.set entry.querySelector("img").getAttribute("title"), data={} # Adding champ to listing.
				data.roles = entry.querySelector("i").innerText.trim().split(", ")		 # Fetching recommended roles.
				@url2doc(entry.querySelector("a").getAttribute "href").then ((rec) ->	 # Parsing recommendations page.
					for table, idx in rec.querySelectorAll(".data_table.sortable_table") # Parsing underlying tables.
						@[['allies', 'victims', 'nemesises'][idx]] = 					 # Parsing tables to 3 lists.
							for entry in table.querySelectorAll "tr" when entry = entry.querySelector "img" # Checking.
								entry.getAttribute "title"								 # Register champ name.
				).bind data
			)
			# Storing data for later usage.
			@cache = @json
			@stamp = Date.now()
		).bind @

	reload: () ->
		try
			if @stamp and (Date.now() - @stamp) / (24*60*60*1000) < 3
				@json = @cache
				@champions if @champions.size

	recommend: (bans, team, foes, lanesort = true) ->
		console.log lanesort
		# Primary setup.
		recom = new Map()
		cover = new Set()
		# Adding all recommended synergies.
		for champ in team
			champ = @champions.get champ
			recom.bump(synergy)	for synergy in champ.allies
			cover.add(role)		for role	in champ.roles
		# Adding all recommended counters and removing nemesisi.
		for champ in foes
			champ = @champions.get champ
			recom.bump(nemesis)		for nemesis	in champ.nemesises
			recom.bump(victim,-1)	for victim	in champ.victims
		# Removing impossible chars.
		for src in [bans, team, foes]
			recom.delete(champ) for champ in src
		# Bonus for role coverage (optional).
		if lanesort
			for advice from recom
				for role in @champions.get(name = advice[0]).roles when not cover.has role
					recom.set name, advice[1] * 2
					break				
		# Finalizing.
		[...recom].filter((x) -> x[1] > 0).sort((a, b) -> b[1] - a[1])[...15].map (sub) -> sub[0]
		
	# --Properties goes here.
	@getter 'cache', ()		-> localStorage.getItem(cache_key)
	@setter 'cache', (val)	-> localStorage.setItem(cache_key, val)
	@getter 'stamp', ()		-> localStorage.getItem(stamp_key)
	@setter 'stamp', (val)	-> localStorage.setItem(stamp_key, val)
	@getter 'json', ()		-> JSON.stringify [...@champions]
	@setter 'json', (val)	-> @champions = new Map JSON.parse val
# -------------------- #
class UI
	stub		= "-----"
	row_names	= ['bans', 'team', 'foes']

	# --Methods goes here.
	constructor: () ->
		# Primary setup.
		@db		= new Stat
		@db.ready.then (-> @init()).bind @
		@out	= document.getElementById 'advisor'
		@in		= {team: [], bans: [], foes: []}
		# Error handlers setup.
		window.onerror = (msg, url, ln, col, e) ->
			console.error e
			alert "#{e.toString()} !\nLine №#{ln}[#{col}], #{new URL(url).pathname}"
			return true

	init: () ->
		# Initial setup.
		rows	= (document.getElementById row for row in row_names)
		ctable	= ['crimson', 'cyan', 'coral']
		@cache	= new Map([['',@name2option()]].concat([name,@name2option(name)] for name from @db.champions.keys()))
		# Rows filling.
		for idx in [2..20] # 4 team slots, 10 ban slots, 5 foe slots.
			sel = document.createElement('select')
			@in[row_names[factor = idx % 4 % 3]].push sel
			sel.setAttribute 'class', 'selector'
			sel.innerHTML	= @name2option()
			sel.style.color	= ctable[factor]
			sel.addEventListener 'change', @sync.bind @
			rows[factor].appendChild sel
		# Erasers setup.
		for row, idx in row_names
			eraser = document.createElement("span")
			eraser.innerText = 'CLEAR'
			eraser.setAttribute 'class', 'eraser'
			eraser.style.color = eraser.style.borderColor = ctable[idx]
			eraser.addEventListener 'click', @clear.bind @, row
			rows[idx].appendChild eraser
		# Additional controls.
		(@in.lanesort = document.getElementById('lanesort')).addEventListener 'change', @refill.bind @
		# Finalization.
		@refill()
		document.getElementById('stub').style.visibility = 'hidden'
		document.getElementById('ui').style.visibility = 'visible'

	clear: (row_name) ->
		(sel.value = stub) for sel in @in[row_name]
		@refill()

	fetch: (row_name, force) ->
		val for sel in @in[row_name] when (stub isnt val = unescape(sel.value)) or force

	refill: () ->
		# Primary loop
		for row, idx in row_names
			# Loop setup.
			pool = new Map @cache
			# Deleting entries from opposing rows.
			for counter, cidx in row_names when cidx isnt idx
				pool.delete(excl) for excl in @fetch counter
			# Correcting current rows.
			for sel, pos in @in[row]
				subpool			= new Map pool
				subpool.delete(choice) for choice, scan in @fetch(row, true) when scan isnt pos
				prev			= sel.value
				sel.innerHTML	= [...subpool.values()].join ''
				sel.value		= prev
		# Finalization.
		@sync()

	sync: () ->
		vals = @db.recommend ...(@fetch(row) for row in row_names), @in.lanesort.checked
		@out.innerHTML = (@name2option(champ) for champ from vals).join ''

	name2option: (name = stub) ->
		"<option value='#{escape(name)}'>#{name}</option>"				
#.} [Classes]

# ==Main code==
window.ui = new UI