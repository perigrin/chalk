package C; sub new { bless {l => []}, shift } sub l { $_[0]{l} } package main; my $o = C->new; push @{$o->l}, 1, 2; my $p = C->new; print scalar(@{$o->l}), scalar(@{$p->l}), "\n";
