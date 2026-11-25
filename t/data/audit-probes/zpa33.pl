my %h; sub inc { $_[0]++ } inc($h{a}{b}); print join(",", map { "$_=" . join("", %{$h{$_}}) } sort keys %h), "\n";
