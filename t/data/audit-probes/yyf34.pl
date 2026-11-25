my $r; my $ok = eval { my @l = @$r; 1 }; print $ok ? "ok" : "died", defined $r ? "d" : "u", "\n";
