local $SIG{__WARN__} = sub { print "W:$_[0]" }; warn "w\n"; warn "no newline"; print "\n";
