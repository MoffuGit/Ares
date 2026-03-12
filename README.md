Is really weird that the monitor fails that much, and even more that fails with
the next two cases:
a completion has the next field set and not null
a completion is active

for me this don't make sense because there should not be a case where the same completion is used twice
for every watcher request we create a watcher entry (this watcher entry has his own completion and watcher)
and even if two watchers share hte same path, the xev system handle that case as well
is not the callback becasue they don't get to trigger during the filetree set up,


this don't make sense:
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active
[1] error(libxev_kqueue): invalid state in submission queue state=.active

and this make even less:
Thread 14 Crashed:
0   libsystem_kernel.dylib        	       0x1996115b0 __pthread_kill + 8
1   libsystem_pthread.dylib       	       0x19964b888 pthread_kill + 296
2   libsystem_c.dylib             	       0x199550850 abort + 124
3   libcore.dylib                 	       0x13ae0d268 posix.abort + 20
4   libcore.dylib                 	       0x13adf9f24 debug.defaultPanic + 136
5   libcore.dylib                 	       0x13ae08924 debug.FullPanic((function 'defaultPanic')).reachedUnreachable + 52
6   libcore.dylib                 	       0x13adfbef8 debug.assert + 56
7   libcore.dylib                 	       0x13af05314 queue.Intrusive(backend.kqueue.Completion).push + 56
8   libcore.dylib                 	       0x13af02db8 backend.kqueue.Loop.submit + 1924
9   libcore.dylib                 	       0x13af06ce4 backend.kqueue.Loop.tick + 352
10  libcore.dylib                 	       0x13af083d8 backend.kqueue.Loop.run + 268
11  libcore.dylib                 	       0x13af14600 monitor.Thread.threadMain_ + 168
12  libcore.dylib                 	       0x13af144bc monitor.Thread.threadMain + 60
13  libcore.dylib                 	       0x13af14470 Thread.callFn__anon_44102 + 32
14  libcore.dylib                 	       0x13af143f4 Thread.PosixThreadImpl.spawn__anon_44076.Instance.entryFn + 116
15  libsystem_pthread.dylib       	       0x19964bc08 _pthread_start + 136
16  libsystem_pthread.dylib       	       0x199646ba8 thread_start + 8


