sub c { wantarray ? "L" : "S" } my %h = (k => c()); my $r = [c()]; print "$h{k}@$r", c() x 2, "\n";
