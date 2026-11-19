local $SIG{__DIE__} = sub { print "D:$_[0]" }; eval { die "x\n" }; print "end $@";
