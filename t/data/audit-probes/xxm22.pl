sub mk { my %x; $x{n} = shift; \%x } my ($p,$q) = (mk(1), mk(2)); $p->{n}++; print "$p->{n}$q->{n}\n";
