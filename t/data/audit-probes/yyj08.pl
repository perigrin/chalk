my %d = (a => sub { "A" }, b => sub { "B$_[0]" }); my $k="b"; print $d{a}->(), $d{$k}->(1), $d{b}(2), &{$d{a}}(), "\n";
