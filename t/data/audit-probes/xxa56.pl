sub f { $_[0] = wantarray ? "l" : defined(wantarray) ? "s" : "v" } my ($p,$q,$r); my @l = f($p); my $s = f($q); f($r); print "$p$q$r\n";
