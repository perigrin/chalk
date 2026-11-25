use Data::Dumper; $Data::Dumper::Sortkeys = 1; $Data::Dumper::Indent = 0; $Data::Dumper::Terse = 1; print Dumper({ a => 1, b => [1,2] }), "\n";
