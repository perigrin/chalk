sub mk { my %h = (n => $_[0]); \%h } my @o = map { mk($_) } 1..3; $o[0]{n} = 9; print join(",", map { $_->{n} } @o), "\n";
