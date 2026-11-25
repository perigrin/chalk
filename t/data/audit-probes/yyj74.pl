sub mk { my @a = @_; \@a } my $p = mk(1,2); my $q = mk(3); push @$p, 9; print "@$p|@$q\n";
