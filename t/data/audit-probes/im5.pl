package T; sub TIEHASH { bless {}, shift } sub FETCH { "f:$_[1]" } sub STORE { print "S:$_[1]\n" } package main; tie my %h, "T"; $h{a} = 1; print $h{b}, "\n";
