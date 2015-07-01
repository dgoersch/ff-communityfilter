# ff-communityfilter
Filters JSON data from ffmap-backend base on filter strings

## communityfilter.pl

Reads nodes.json and graph.json from ffmap-backend and create filtered ones for several communities.
Every community has its own target directory, can have several filter strings an decide to create legacy.json (for the old ffmap-d3) or not and to save the contacts or not.

Every node its name matches the whitelist, the filterstring or is flagged as a gateway, will be taken to the target json.

## communityfilter.ini

Config file for communityfiler.pl. Needs the sourcedir and legacyfilter in the general section and at least one community-section with targetdir, legacy- and contacts-switch an one oder more filterstring(s).

## Requirements

Communityfilter needs 'jq', File::Basename-, Config:IniFiles- and JSON-Perl modules installed and sourcefiles from ffmap-backend.
