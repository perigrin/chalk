my @s; push @s,{n=>$_} for 1..3; $_->{n}*=2 for @s; my ($m)=sort { $b->{n} <=> $a->{n} } @s; $m->{n}=0; print join("", map { $_->{n} } @s), "\n";
