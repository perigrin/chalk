my $acc = ""; sub rec { my $n = shift; $acc .= $n; rec($n - 1) if $n; $acc .= $n } rec(2); print "$acc\n";
