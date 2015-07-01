#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;
use Config::IniFiles;
use JSON;

# reading configfile
my $configfile = exists $ARGV[0] ? $ARGV[0] : dirname($0)."/communityfilter.ini";
my $cfg          = Config::IniFiles->new(-file => $configfile ) or &print_usage;
my $sourcedir    = $cfg->val('general', 'sourcedir');
my $legacyfilter = $cfg->val('general', 'legacyfilter');
my @whitelist    = $cfg->val('general', 'whitelist');

# open source files
open(my $nsfh, '<:encoding(UTF-8)', "$sourcedir/nodes.json") or die "Could not open source file '$sourcedir/nodes.json': $!";
open(my $gsfh, '<:encoding(UTF-8)', "$sourcedir/graph.json") or die "Could not open source file '$sourcedir/graph.json': $!";

# read source files
my $nodes_source_text = join("", <$nsfh>);
my $graph_source_text = join("", <$gsfh>);

# running through communities
for my $community (@{$cfg->{mysects}}) {
    my $local_nodes_source_text = $nodes_source_text;
    my $local_graph_source_text = $graph_source_text;

    # skip general section
    if($community eq 'general') { next; }

    # read community settings
    my $targetdir     = $cfg->val($community, 'targetdir');
    my $create_legacy = $cfg->val($community, 'legacy');
    my $keep_contacts = $cfg->val($community, 'contacts');
    my @filters       = $cfg->val($community, 'filter');

    # create target directory
    &mk_subdirs($targetdir,0700);

    #open target files
    open(my $ntfh, '>:encoding(UTF-8)', "$targetdir/nodes.json") or die "Could not open target file '$targetdir/nodes.json': $!";
    open(my $gtfh, '>:encoding(UTF-8)', "$targetdir/graph.json") or die "Could not open target file '$targetdir/graph.json': $!";

    # read json from nodes.json
    my $json = decode_json($local_nodes_source_text);

    my $filtered_nodes;
    my @macs;

    # running through nodes
    for my $node (keys(%{$json->{nodes}})) {

        # if node is a gateway or in whitelist
        if ( ($json->{nodes}->{$node}->{flags}->{gateway}) || ($json->{nodes}->{$node}->{nodeinfo}->{hostname} ~~ @whitelist) ) {

            # store node to target var
            $filtered_nodes -> {$json->{nodes}->{$node}->{nodeinfo}->{node_id}} = $json->{nodes}->{$node};

            # store all macs of this node
            push @macs, $json->{nodes}->{$node}->{nodeinfo}->{network}->{mac};
            for my $mesh_interface (@{$json->{nodes}->{$node}->{nodeinfo}->{network}->{mesh_interfaces}}) {
                push @macs,$mesh_interface;
            }
            next;
        }

        # running through filters
        for my $filter (@filters) {

            # if nodes name matches filterstring
            if ( $json->{nodes}->{$node}->{nodeinfo}->{hostname} =~ /^$filter/i ) {
                # store node to target var
                $filtered_nodes -> {$json->{nodes}->{$node}->{nodeinfo}->{node_id}} = $json->{nodes}->{$node};

                # store all macs of this node
                push @macs, $json->{nodes}->{$node}->{nodeinfo}->{network}->{mac};
                for my $mesh_interface (@{$json->{nodes}->{$node}->{nodeinfo}->{network}->{mesh_interfaces}}) {
                    push @macs,$mesh_interface;
                }

                # if community wants no contacts
                if( $keep_contacts eq 'no' ) {

                    # delete owner information
                    delete $filtered_nodes->{ $json->{nodes}->{$node}->{nodeinfo}->{node_id} }->{nodeinfo}->{owner};
                }
            }
        }
    }

    # build target structure
    my $new_nodes_json;
    $new_nodes_json -> {'timestamp'} = $json->{timestamp};
    $new_nodes_json -> {'nodes'}     = $filtered_nodes;
    $new_nodes_json -> {'version'}   = 1;

    # write target nodes.json
    print $ntfh encode_json($new_nodes_json);



    # read json from graph.json
    my $graph = decode_json($local_graph_source_text);
    my @filtered_graph_nodes;

    my $index_old = 0;
    my $index_new = 0;
    my @filtered_graph_index;

    # running through 'nodes' of graph.json
    for my $graph_node (@{$graph->{batadv}->{nodes}}) {

        # if node has a stored mac address
        if($graph_node->{'id'} ~~ @macs) {
            my $node;

            # copy node to target var
            if($graph_node->{'node_id'}) { $node -> {'node_id'} = $graph_node->{'node_id'}; }
            $node -> {'id'}      = $graph_node->{'id'};
            push @filtered_graph_nodes, $node;

            # remembers nodes position in old list
            $filtered_graph_index[$index_old] = $index_new;
            $index_new++
        }
        $index_old++;
    }


    my @filtered_graph_links;

    # running through 'links' of graph.json
    for my $graph_link (@{$graph->{batadv}->{links}}) {

        # if link has a stored node position in source and target
        if( ($filtered_graph_index[$graph_link->{source}]) && ($filtered_graph_index[$graph_link->{target}]) ) {
            my $new_link;

            # create link entry with recalculated positions
            $new_link -> {'source'}   = $filtered_graph_index[$graph_link->{source}];
            $new_link -> {'target'}   = $filtered_graph_index[$graph_link->{target}];
            $new_link -> {'vpn'}      = $graph_link->{vpn};
            $new_link -> {'bidirect'} = $graph_link->{bidirect};
            $new_link -> {'tq'}       = $graph_link->{tq};
            push @filtered_graph_links, $new_link;
        }
    }

    # build target structure
    my $new_batadv;
    $new_batadv -> {'directed'}   = $graph->{batadv}->{directed};
    $new_batadv -> {'graph'}      = $graph->{batadv}->{graph};
    $new_batadv -> {'nodes'}      = \@filtered_graph_nodes;
    $new_batadv -> {'links'}      = \@filtered_graph_links;
    $new_batadv -> {'multigraph'} = $graph->{batadv}->{multigraph};

    my $new_graph_json;
    $new_graph_json -> {'version'} = 1;
    $new_graph_json -> {'batadv'}  = $new_batadv;

    # write target graph.json
    print $gtfh encode_json($new_graph_json);

    # close target files
    close($ntfh);
    close($gtfh);

    # create legacy json file for the old ffmap-d3 id community wants it
    if($create_legacy eq 'yes') {
        system("jq -n -f $legacyfilter --argfile nodes $targetdir/nodes.json --argfile graph $targetdir/graph.json > $targetdir/legacy.json");
    }
}

# close source files
close($nsfh);
close($gsfh);


# print usage
sub print_usage {
    print "USAGE:\n";
    print "$0 [configfile]\n";
    print "  configfile     full path to the config file, default is communityfilter.ini in programm directory\n\n";
    exit(1);
}

# make subdirs with missing dirs
sub mk_subdirs{
    my $dir    = shift;
    my $rights = shift;
    my @dirs   = split(/\//,$dir);

    my $akdir  = '';

    $dir       =~ s/^\s+//;
    $dir       =~ s/\s+$//;
    $dir       =~ s/^\///;
    $dir       =~ s/\/$//;

    for (@dirs){
        $akdir .= $_;
        if (!-e $akdir){
            my $res = mkdir($akdir,$rights);
            return 0 if ($res != 1);
        }
        $akdir .= '/';
    }
    return 1;
}

