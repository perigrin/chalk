package C; sub new { bless [], shift } sub add { my $s = shift; push @$s, @_; $s } sub sum { my $t = 0; $t += $_ for @{$_[0]}; $t } package main; print C->new->add(1, 2)->add(3)->sum, "\n";
