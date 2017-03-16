classdef PluginMenu < hgsetget
    % PluginMenu - Hierarchical menu for all DENSEanalysis plugins
    %
    %   This class provides a menu which displays all plugins in a
    %   hierarchy and also provides basic menu interaction including
    %   enabling/disabling menu items as well as mouse rollover effects.
    %
    % USAGE:
    %   pm = plugins.PluginMenu(manager, parent)
    %
    % INPUTS:
    %   manager:    Handle, Handle to a PluginManager instance
    %
    %   parent:     Handle, Graphics handle to the uimenu in which to place
    %               this PluginMenu
    %
    % OUTPUTS:
    %   pm:         Object, instance of the PluginMenu that can be used to
    %               manipulate the menu that is created by the constructor

    properties
        Menu        % Handle to the main uimenu
        Manager     % Handle to the plugin.PluginManager singleton
        Menus       % Handles to all sub-menus
    end

    properties (Dependent)
        Classes     % Array of meta-class objects for each plugin
        Loading     % Boolean indicating whether the menu is being loaded
        Plugins     % Handles to instances of all plugins themselves
    end

    properties (Hidden)
        reloadmenu = []     % Handle to the 'Reload Plugins' menu item
        managemenu = []     % Handle to the 'Import Plugin' menu item
        loading = false;    % Shadow loading property
        dellistener         % Listener for when a plugin is removed
        menulistener        % Listener for when the menu is destroyed
    end

    properties (Dependent, Hidden)
        internalmenus       % Array of menu items that we manage
    end

    events
        Status  % Event to be fired when a status message is available
    end

    methods
        function self = PluginMenu(manager, parent)
            % PluginMenu - Constructor for the PluginMenu class
            %
            % USAGE:
            %   m = plugins.PluginMenu(manager, parent)
            %
            % INPUTS:
            %   manager:    plugins.PluginManager object
            %
            %   parent:     Handle, Parent to use to properly place the
            %               menu. Can be either a figure or uimenu handle
            %
            % OUTPUTS:
            %   m:          plugins.PluginMenu object

            menulabel = 'Plugins';

            % If the parent is not specified, create a new uimenu object
            if ~exist('parent', 'var')
                self.Menu = uimenu('Parent', gcf, 'Label', menulabel);
            elseif ishghandle(parent, 'figure')
                self.Menu = uimenu('Parent', parent, 'Label', 'Plugins');
            elseif ishghandle(parent, 'uimenu')
                self.Menu = parent;
            else
                error(sprintf('%s:InvalidParent', mfilename), ...
                    'Parent must be a figure or uimenu handle')
            end


            self.Manager = manager;

            % Add a listener in case any of the plugins are removed as when
            % this occurs, we want to remove that plugin from the menu
            self.dellistener = addlistener(self.Manager, ...
                                           'PluginRemoved', ...
                                           @(s,e)self.refresh());

            % Create the menu and assign all listeners/callbacks
            self.initialize();
        end

        function delete(self)
            % delete - Deletes the menu and all plugins
            %
            % USAGE:
            %   pm.delete()

            % Prior to object deletion, we must remove all listeners to
            % prevent future errors
            delete(self.dellistener);
            delete(self.menulistener);

            % Now be sure to delete the menu itself
            delete(self.Menu);

            % Now actually delete the menu
            delete@handle(self);
        end

        function refresh(self)
            % refresh - Updates all menu items and removed invalid menus
            %
            % USAGE:
            %   pm.refresh()

            % Update menus with only valid menus
            self.Menus = self.Menus(ishghandle(self.Menus));

            classes = {self.Classes.Name};
            tags = get(self.Menus, 'tag');

            if ~isempty(tags)
                exists = ismember(tags, classes);

                % Ignore the internal menu items
                exists = exists | ismember(self.Menus, self.internalmenus);

                % Any classes that were removed will show up as FALSE in tf
                delete(self.Menus(~exists));
                self.Menus(~exists) = [];

                exists = ismember(classes, tags);
            else
                exists = false(size(self.Classes));
            end


            % Any FALSE entries are things that we need to add
            if ~all(exists)
                self.appendMenuItems(self.Plugins(~exists));
            end

            % Get rid of empty menus
            allmenus = findall(self.Menu, 'type', 'uimenu');
            menuitems = cat(1, self.internalmenus, self.Menus(:));
            parents = allmenus(~ismember(allmenus, menuitems));

            kids = get(parents, 'children');
            if ~iscell(kids); kids = {kids}; end
            ismt = cellfun(@isempty, kids);

            delete(parents(ismt));
        end

        function reload(self)
            % reload - Clears and then reinitialize all plugins
            %
            %   This method reloads all plugins regardless of whether they
            %   have been removed or not from the current menu.
            %
            % USAGE:
            %   self.reload()

            self.Loading = true;

            % Reload all plugins
            self.Manager.clear();

            % Remove the reload itself
            self.reset();
            delete(self.internalmenus);

            self.Manager.refresh();

            % If there was a menu before, be sure to keep it there
            if ishghandle(self.Menu)
                self.reset();
            end

            self.Loading = false;
        end

        function remove(self, index)
            % remove - Remove a plugin menu item by index
            %
            % USAGE:
            %   pm.remove(index)
            %
            % INPUTS:
            %   index:  Integer, index indicating which menu item to
            %           remove. Alternately, an array of indices can be
            %           provided

            try
                todelete = self.Plugins(index);
            catch ME
                if strcmpi(ME.identifier, 'MATLAB:badsubscript')
                    error(sprintf('%s:InvalidSubscript', mfilename), ...
                        'Index must be between 1 and %d', numel(self.Plugins));
                else
                    rethrow(ME);
                end
            end

            arrayfun(@delete, todelete)
        end

        function reset(self)
            % reset - Forces a hard reload of all plugins
            %
            %   This method does NOT reload removed plugins but rather does
            %   a hard refresh of the plugins which are loaded when it is
            %   called. If you want to reload even removed plugins, be sure
            %   to use plugins.PluginMenu.reload().
            %
            % USAGE:
            %   pm.reset()

            delete(self.Menus);
            self.initialize();
        end
    end

    %--- Get / Set Methods ---%
    methods
        function res = get.Classes(self)
            res = self.Manager.Classes;
        end

        function res = get.Loading(self)
            res = self.loading;
        end

        function res = get.Plugins(self)
            res = self.Manager.Plugins;
        end

        function res = get.internalmenus(self)
            res = [self.managemenu; self.reloadmenu];
        end

        function set.Loading(self, val)
            self.loading = val;
        end
    end

    methods (Hidden)
        function appendMenuItems(self, plugins)
            % appendMenuItems - Adds the requested plugins to the menu
            %
            % USAGE:
            %   pm.appendMenuItems(plugins)
            %
            % INPUTS:
            %   plugins:    [M x 1] Handle, Handles to an array of
            %               subclasses of plugin.DENSEanalysisPlugin.
            %               These plugins will be added to the menu based
            %               upon the package and sub-package that they are
            %               contained within.

            for k = 1:numel(plugins)
                plugin = plugins(k);

                classname = class(plugin);
                metaclass = meta.class.fromName(classname);
                package = metaclass.ContainingPackage;
                pieces = regexp(classname, '\.', 'split');

                parent = self.Menu;

                % Create the heirarchy of parent menus
                for m = 1:(numel(pieces) - 1)
                    tagname = sprintf('%s.', pieces{1:m});
                    tagname(end) = '';

                    % Find any uimenu objects with this same tag and use
                    % these as the parents
                    previous = parent;
                    parent = findobj(self.Menu, 'tag', tagname);

                    if isempty(package.FunctionList) || ...
                        ~ismember('getName', {package.FunctionList.Name})
                        parent = previous;
                        continue
                    else
                        label = feval([package.Name, '.getName']);
                    end

                    if isempty(parent)
                        parent = uimenu('Parent',   self.Menu, ...
                                        'Label',    label, ...
                                        'Tag',      tagname);
                    end
                end

                fcn = @(s,e,varargin)self.callback(plugin, varargin{:});
                menu = uimenu(plugin, parent, fcn);

                self.Menus = cat(1, self.Menus(:), menu(:));
            end
            drawnow
        end

        function callback(self, plugin, varargin)
            % callback - To be executed when a plugin is selected
            %
            % USAGE:
            %   pm.callback(plugin)
            %
            % INPUTS:
            %   plugin: Handle, Handle to the DENSEanalysisPlugin
            %           subclass instance

            inputs = cat(2, {self.Manager.Data}, varargin);

            % If we are debugging, we want any errors to be caught inside
            % of the function where the error actually was
            if isDebug()
                plugin.validate(inputs{:});
                plugin.run(inputs{:});
            else
                try
                    plugin.validate(inputs{:});
                    plugin.run(inputs{:});
                catch ME
                    % All errors should be thrown as an error dialog
                    plugin.setStatus('');
                    msg = sprintf('%s Plugin failed to complete.', plugin.Name);
                    msg = {msg, '', sprintf('ERROR: %s', ME.message)};
                    errordlg(msg, 'Plugin Error');
                end
            end

            try
                plugin.cleanup()
            catch ME
                fprintf('Plugin cleanup for %s was unsuccessful.\n', class(self));
                disp(getReport(ME));
            end
        end

        function checkAvailability(self, varargin)
            % checkAvailability - Determine if a plugin is viable
            %
            %   Looks at all plugins and determines if they are available
            %   and changes the "Enable" state to match.
            %
            % USAGE:
            %   pm.checkAvailability

            if self.Loading
                return;
            end

            inputs = cat(2, {self.Manager.Data}, varargin);

            for k = 1:numel(self.Plugins)
                plugin = self.Plugins(k);

                [isavailable, msg] = plugin.isAvailable(inputs{:});

                menus = findobj(self.Menus, 'tag', class(plugin));

                if isavailable
                    set(menus, 'Enable', 'on', 'UserData', '');
                    tooltip = plugin.Description;
                else
                    set(menus, 'Enable', 'off', 'UserData', msg);
                    tooltip = msg;
                end

                % Update the tooltip to display help information
                arrayfun(@(x)setToolTipText(x, tooltip), menus);
            end
        end

        function initialize(self)
            % initialize - Creates all menu items and callbacks
            %
            %   This method should only be called internally to initialize
            %   the menu and assign all of the necessary callbacks.
            %
            % USAGE:
            %   pm.initialize()

            set(self.Menu, 'tag', 'plugins')

            % State that we are loading so that the menu is disabled while
            % we create everything
            self.Loading = true;

            % Check availability of all plugins every time we click the
            % main plugin menu item
            set(self.Menu, 'callback', @(s,e)self.checkAvailability());


            self.menulistener = addlistener(self.Menu, ...
                                            'ObjectBeingDestroyed', ...
                                            @(s,e)delete(self(isvalid(self))));

            % Ensure that there are always reload and manage menu items
            if isempty(self.managemenu) || ~ishghandle(self.managemenu)
                self.managemenu = uimenu( ...
                    'Parent',      self.Menu, ...
                    'Separator',   'off', ...
                    'Callback',    @(s,e)plugins.PluginDialog(self.Manager), ...
                    'Label',       'Manage Plugins');

                setToolTipText(self.managemenu, 'Manage installed plugins')
            end

            if isempty(self.reloadmenu) || ~ishghandle(self.reloadmenu)
                self.reloadmenu = uimenu('Parent',      self.Menu,  ...
                                         'Separator',   'on', ...
                                         'Callback',    @(s,e)self.reload(), ...
                                         'Label',       'Reload Plugins');

                setToolTipText(self.reloadmenu, 'Reload all active plugins')
            end

            % Do a refresh which actually creates all of the sub-menus for
            % each of the loaded plugins
            self.refresh();

            % Re-order the menu to ensure that the reload option is
            % always the last menu item
            kids = get(self.Menu, 'children');
            isinternal = ismember(kids, self.internalmenus);
            newkids = cat(1, self.internalmenus, kids(~isinternal));
            set(self.Menu, 'children', newkids);

            % Enable the menu now that we have created everything
            self.Loading = false;
        end

        function importPlugin(self)
            % importPlugin - Callback for importing a plugin using the menu

            u = [];
            [status, info] = self.Manager.import('', @(s,e)callback(e));
            delete(u);

            % The user hit cancel and no plugin was imported
            if isempty(info); return; end

            name = getfield(info, 'name', 'UNKNOWN');

            if status
                msg = sprintf('%s Plugin Installed Successfully', name);
                msgbox(msg);

                % Now reload the plugin menu
                self.reload();
            else
                msg = sprintf('%s Plugin Installation Failed!', name);
                errordlg(msg);
            end

            function callback(~)
            end
        end
    end
end

function bool = isDebug()
    % is_debug - Determines whether dbstop if error is used
    %
    % USAGE:
    %   bool = is_debug()
    %
    % OUTPUTS:
    %   bool:   Boolean, 0 if debug status is off and 1 if it is on.

    db = dbstatus();
    bool = ~isempty(db) && any(strcmpi({db.cond}, 'error'));
end

function setToolTipText(hmenu, txt)
    % setToolTipText - Sets the tooltip for a uimenu item
    %
    %   Tooltips are used to display the description of the plugin (when it
    %   is available) or displays the reason why the plugin is disabled if
    %   it is disabled.
    %
    % USAGE:
    %   setToolTipText(hmenu, text)
    %
    % INPUTS:
    %   hmenu:  Handle, uimenu graphics handle to set the tooltip for
    %
    %   text:   String, Tooltip to associate with the uimenu item

    jmenu = getappdata(hmenu, 'java');

    % If we don't yet know the java handle, then get it and cache it
    if isempty(jmenu)
        try
            jmenu = getJavaMenu(hmenu);
        catch ME
            % If the java menu hasn't been rendered (some operating
            % systems), then just silently ignore this and try again later
            if strcmp(ME.identifier, 'getJavaMenu:MenuNotFound')
                return
            else
                rethrow(ME);
            end
        end
        setappdata(hmenu, 'java', jmenu);
    end

    jmenu.setToolTipText(txt);
end
