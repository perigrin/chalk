local $SIG{__DIE__} = sub { print "H:$_[0]" }; eval { die "x\n" }; print "after:$@";
