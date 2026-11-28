my $d = {l => [1,2]}; my $e = $d->{l}; $d->{l} = [9]; print "@$e|@{$d->{l}}\n";
