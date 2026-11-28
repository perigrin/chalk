$@ = "old"; my $v = eval { $@ }; print defined $v && $v eq "" ? "empty" : "kept:$v", "\n";
