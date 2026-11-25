my %h = (1 => "a", 1.0 => "b", "1.0" => "c", 01 => "d", "01" => "e"); print join(",", map { "$_=$h{$_}" } sort keys %h), "\n";
