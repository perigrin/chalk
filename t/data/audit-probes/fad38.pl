use feature 'try'; no warnings; our $g=1; sub f { local $g=2; die "x\n" } try { f() } catch ($e) { print "c:$g $e" }
