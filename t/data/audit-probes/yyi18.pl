sub inc { $_[0]++ } my $o={n=>1, l=>[5]}; inc($o->{n}); inc($o->{l}[0]); inc($o->{l}->[0]); inc(@{$o->{l}}); print "$o->{n}$o->{l}[0]\n";
