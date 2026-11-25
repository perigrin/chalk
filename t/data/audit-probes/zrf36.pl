my $o={n=>1}; my $p=$o; $p->{n}++; my $v=$o->{n}; $o={n=>9}; print "$v$p->{n}$o->{n}\n";
