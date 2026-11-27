sub f { my ($x) = @_; \$x } my $v = 1; my $r = f($v); $$r = 5; print "$v$$r\n";
