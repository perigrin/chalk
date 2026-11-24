my $o={l=>[1]}; sub ad { push @{$_[0]{l}},2 } my @c=@{$o->{l}}; ad($o); print scalar(@c),"\n";
