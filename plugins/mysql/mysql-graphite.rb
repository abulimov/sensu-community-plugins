#!/usr/bin/env ruby
#
# Push mysql stats into graphite
# ===
#
# Created by Pete Shima - me@peteshima.com
# Additional hacks by Joe Miller - https://github.com/joemiller
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.
#
# NOTE: This plugin will attempt to get replication stats but the user must have 
#  SUPER or REPLICATION CLIENT privileges to run 'SHOW SLAVE STATUS'. It will
#  silently ignore and continue if 'SHOW SLAVE STATUS' fails for any reason.
#  The key 'slaveLag' will not be present in the output.
# 

require "rubygems" if RUBY_VERSION < "1.9.0"
require 'sensu-plugin/metric/cli'
require 'mysql2'
require 'socket'

class Mysql2Graphite < Sensu::Plugin::Metric::CLI::Graphite

  option :host,
    :short => "-h HOST",
    :long => "--host HOST",
    :description => "Mysql Host to connect to",
    :required => true

  option :port,
    :short => "-P PORT",
    :long => "--port PORT",
    :description => "Mysql Port to connect to",
    :proc => proc {|p| p.to_i },
    :default => 3306

  option :username,
    :short => "-u USERNAME",
    :long => "--user USERNAME",
    :description => "Mysql Username",
    :required => true

  option :password,
    :short => "-p PASSWORD",
    :long => "--pass PASSWORD",
    :description => "Mysql password",
    :default => ""

  option :scheme,
    :description => "Metric naming scheme, text to prepend to metric",
    :short => "-s SCHEME",
    :long => "--scheme SCHEME",
    :default => "#{Socket.gethostname}"


  def run

    #props to https://github.com/coredump/hoardd/blob/master/scripts-available/mysql.coffee

    general = {
      'Bytes_received' =>         'rxBytes',                  
      'Bytes_sent' =>             'txBytes',                  
      'Key_read_requests' =>      'keyRead_requests',          
      'Key_reads' =>              'keyReads',                  
      'Key_write_requests' =>     'keyWrite_requests',         
      'Key_writes' =>             'keyWrites',                
      'Binlog_cache_use' =>       'binlogCacheUse',            
      'Binlog_cache_disk_use' =>  'binlogCacheDiskUse',       
      'Max_used_connections' =>   'maxUsedConnections',       
      'Aborted_clients' =>        'abortedClients',            
      'Aborted_connects' =>       'abortedConnects',           
      'Threads_connected' =>      'threadsConnected',          
      'Open_files' =>             'openFiles',                 
      'Open_tables' =>            'openTables',               
      'Opened_tables' =>          'openedTables',             
      'Seconds_Behind_Master' =>  'slaveLag',                 
      'Select_full_join' =>       'fullJoins',                
      'Select_full_range_join' => 'fullRangeJoins',            
      'Select_range' =>           'selectRange',              
      'Select_range_check' =>     'selectRange_check',        
      'Select_scan' =>            'selectScan'     
      }      

    queryCache = {
      'Qcache_queries_in_cache' =>  'queriesInCache',            
      'Qcache_hits' =>              'cacheHits',                 
      'Qcache_inserts' =>           'inserts',                   
      'Qcache_not_cached' =>        'notCached',                 
      'Qcache_lowmem_prunes' =>     'lowMemPrunes'             
    }

    commands = {
      'Com_admin_commands' => 'admin_commands',
      'Com_begin' =>          'begin',
      'Com_change_db' =>      'change_db',
      'Com_commit' =>         'commit',
      'Com_create_table' =>   'create_table',
      'Com_drop_table' =>     'drop_table',
      'Com_show_keys' =>      'show_keys',
      'Com_delete' =>         'delete',
      'Com_create_db' =>      'create_db',
      'Com_grant' =>          'grant',
      'Com_show_processlist' => 'show_processlist',
      'Com_flush' =>          'flush',
      'Com_insert' =>         'insert',
      'Com_purge' =>          'purge',
      'Com_rollback' =>       'rollback',
      'Com_select' =>         'select',
      'Com_set_option' =>     'set_option',
      'Com_show_binlogs' =>   'show_binlogs',
      'Com_show_databases' => 'show_databases',
      'Com_show_fields' =>    'show_fields',
      'Com_show_status' =>    'show_status',
      'Com_show_tables' =>    'show_tables',
      'Com_show_variables' => 'show_variables',
      'Com_update' =>         'update',
      'Com_drop_db' =>        'drop_db',
      'Com_revoke' =>         'revoke',
      'Com_drop_user' =>      'drop_user',
      'Com_show_grants' =>    'show_grants',
      'Com_lock_tables' =>    'lock_tables',
      'Com_show_create_table' => 'show_create_table',
      'Com_unlock_tables' =>  'unlock_tables',
      'Com_alter_table' =>    'alter_table'
    }

    counters = {                                                    
      'Handler_write' =>              'handlerWrite',             
      'Handler_update' =>             'handlerUpdate',            
      'Handler_delete' =>             'handlerDelete',             
      'Handler_read_first' =>         'handlerRead_first',        
      'Handler_read_key' =>           'handlerRead_key',          
      'Handler_read_next' =>          'handlerRead_next',         
      'Handler_read_prev' =>          'handlerRead_prev',         
      'Handler_read_rnd' =>           'handlerRead_rnd',          
      'Handler_read_rnd_next' =>      'handlerRead_rnd_next',     
      'Handler_commit' =>             'handlerCommit',            
      'Handler_rollback' =>           'handlerRollback',          
      'Handler_savepoint' =>          'handlerSavepoint',         
      'Handler_savepoint_rollback' => 'handlerSavepointRollback'
    }

    innodb = {
      'Innodb_buffer_pool_pages_total' =>   'bufferTotal_pages',        
      'Innodb_buffer_pool_pages_free' =>    'bufferFree_pages',         
      'Innodb_buffer_pool_pages_dirty' =>   'bufferDirty_pages',        
      'Innodb_buffer_pool_pages_data' =>    'bufferUsed_pages',         
      'Innodb_page_size' =>                 'pageSize',                 
      'Innodb_pages_created' =>             'pagesCreated',             
      'Innodb_pages_read' =>                'pagesRead',                
      'Innodb_pages_written' =>             'pagesWritten',             
      'Innodb_row_lock_current_waits' =>    'currentLockWaits',         
      'Innodb_row_lock_waits' =>            'lockWaitTimes',            
      'Innodb_row_lock_time' =>             'rowLockTime',              
      'Innodb_data_reads' =>                'fileReads',                
      'Innodb_data_writes' =>               'fileWrites',                
      'Innodb_data_fsyncs' =>               'fileFsyncs',                
      'Innodb_log_writes' =>                'logWrites',                
      'Innodb_rows_updated' =>              'rowsUpdated',              
      'Innodb_rows_read' =>                 'rowsRead',                 
      'Innodb_rows_deleted' =>              'rowsDeleted',               
      'Innodb_rows_inserted' =>             'rowsInserted'
    }

    begin
      mysql = Mysql2::Client.new(
        :host => config[:host], 
        :port =>config[:port], 
        :username => config[:username], 
        :password => config[:password]
        )      

      results = mysql.query("SHOW GLOBAL STATUS")
    rescue => e
      puts e.message
    end
    
    results.each do |row|
      if general.include?(row["Variable_name"]) then
        output "#{config[:scheme]}.mysql.general.#{general[row["Variable_name"]]}", row["Value"]
      end

      if queryCache.include?(row["Variable_name"]) then
        output "#{config[:scheme]}.mysql.querycache.#{queryCache[row["Variable_name"]]}", row["Value"]
      end

      if commands.include?(row["Variable_name"]) then
        output "#{config[:scheme]}.mysql.commands.#{commands[row["Variable_name"]]}", row["Value"]
      end

      if counters.include?(row["Variable_name"]) then
        output "#{config[:scheme]}.mysql.counters.#{counters[row["Variable_name"]]}", row["Value"]
      end

      if innodb.include?(row["Variable_name"]) then
        output "#{config[:scheme]}.mysql.innodb.#{innodb[row["Variable_name"]]}", row["Value"]
      end
    end
    

    begin
      slave_results = mysql.query("SHOW SLAVE STATUS")
      # should return a single element array containing one hash
      slave_results.first.each do |key,value|
        if general.include?(key) then
          # Replication lag being null is bad, very bad, so negativate it here
          if key == 'Seconds_Behind_Master' and value.nil?
            value = -1
          end
          output "#{config[:scheme]}.mysql.general.#{general[key]}", value
        end
      end
    rescue
      # do nothing? often there is no slave status or user doesn't have proper perms
      # so don't pollute the output.
    end
  
  end

end
