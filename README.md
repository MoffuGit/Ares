i already start this but i didn't get to finish it
i need to read a buffer, for that, after a click into a file entry
i would send a message to the core app, the core app woudl then call the lib openBuffer function,
once you open it, you try to read from it, if is the first time you tried to open it, its going to be empty,
the core lib will send an evnet called updateBuffer or something like that, with the entry id of the buffer that got updated,
when this happens the coreApp should tried to read again the info of the buffer, if this happens correctly we can send to the webview a
messge with all the info of the buffer and show it in the view,

lets start impl this and latter we can try adding tabs, splits and views
