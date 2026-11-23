package C; sub new { bless {l=>[]}, shift } sub add { push @{$_[0]{l}}, $_[1] } sub cnt { scalar @{$_[0]{l}} } package main; my $o=C->new; my $b=$o->cnt; $o->add(1); print $b,$o->cnt,"\n";
