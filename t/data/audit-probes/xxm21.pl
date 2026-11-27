sub mk { my @x = @_; \@x } my ($p,$q) = (mk(1), mk(2)); push @$p, 5; print "@$p|@$q\n";
