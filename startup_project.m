% clear command window
clc

projectName = 'EnergyPlus co-simulation toolbox';
matprojFilename = 'matproj.mat';

%% Load state of the editor

proj = slproject.getCurrentProject;
projRootFolder = proj.RootFolder;
if strcmpi(proj.Name,projectName)
    
    disp('============== Loading editor state ================================')
    matproj('LOAD', fullfile(projRootFolder, matprojFilename));
end
disp('===================== Project opened ===================================')


%% Functions
function [] = matproj(varargin)
%
% matproj.m--Saves and loads Matlab "projects". A project consists of the
% m-files that are currently open in the Matlab Editor. Loading a project
% returns the Matlab Editor to the state it was in when the project was
% saved, with the same m-files open to the same lines, the working
% directory set to that of the loaded project and the Matlab search path
% set back to its saved value.
%
% When matproj.m is asked to load a project, it first saves the
% currently-open m-files to a backup project before closing them and
% loading the new project.
%
% MATPROJ by itself, with no input arguments, uses GUI dialogues to ask the
% user whether to save or load a project, after which the user is prompted
% for a project filename (default is 'matproj.mat' in the current
% directory).
%
% MATPROJ('SAVE',FILENAME) saves the current project to the specified file
% without using GUI dialogues.
%
% MATPROJ('LOAD',FILENAME) loads the project from the specified file
% without using GUI dialogues.
%
% MATPROJ('ADD',FILENAME) adds the project from the specified file
% without closing files currently open and without using GUI dialogues.
%
% MATPROJ('SAVE') saves the current project; a file-selection GUI dialogue
% prompts the user to choose a destination file.
%
% MATPROJ('LOAD') loads a project;  a file-selection GUI dialogue prompts
% the user to choose a file for loading.
%
% e.g.,   matproj
%         matproj('save','/home/bartlett/matproj.mat')
%         matproj('load','/home/bartlett/matproj.mat')
%         matproj('add','/home/bartlett/matproj.mat')
%         matproj('save')
%         matproj('load')

% Developed in Matlab 7.12.0.635 (R2011a) on GLNX86
% for the VENUS project (http://venus.uvic.ca/).
% Kevin Bartlett (kpb@uvic.ca), 2012-06-13 18:08
%-------------------------------------------------------------------------

% See
% http://blogs.mathworks.com/community/2011/05/09/r2011a-matlab-editor-api/
% for information on how a lot of this stuff works.

%-------------------------------------------------------------------------
% REVISION HISTORY
%-------------------------------------------------------------------------
%
% 2015-09-18--Added code to "repair" path in the event of a Matlab upgrade.
%
% 2016-02-25--Path repair not working on Windows. Bug fixed.
%
% 2016-04-28--Added action ADD. (user contribution from "Andres").
%
%-------------------------------------------------------------------------

%-------------------------------------------------------------------------
% Possible improvements:
%
% 1) Have a single, central file containing all projects, rather than a
% separate matproj.mat file for each project?
%-------------------------------------------------------------------------

if nargin > 0
    actionStr = varargin{1};
else
    actionStr = '';
end

if nargin > 1
    fileName = varargin{2};
else
    fileName = '';
end

if ~matlab.desktop.editor.isEditorAvailable
    error(['Cannot run ' mfilename ' without Java support.']);
end

% Stick with command-line interface unless user wants GUI.
useGUI = false;

if isempty(actionStr)
    % No action specified. Get via GUI.
    useGUI = true;
    actionList = {'Save', 'Load', 'Add'};
    [Selection,isOk] = listdlg('ListString',actionList,...
        'SelectionMode','single',...
        'ListSize',[160 60],...
        'Name','matproj',...
        'PromptString','Select Project Action');
    
    if isOk
        actionName = actionList{Selection};
    else
        actionName = 'Cancel';
    end
    
    actionStr = lower(actionName);
end

SAVE = 1;
LOAD = 2;
ADD = 3;

if strcmpi(actionStr,'save')
    action = SAVE;
elseif strcmpi(actionStr,'load')
    action = LOAD;
elseif strcmpi(actionStr,'add')
    action = ADD;
elseif strcmpi(actionStr,'cancel')
    return;
else
    error([mfilename '.m--Unrecognised action string ''' actionStr '''.']);
end

if isempty(fileName)
    % No filename specified. Choose it with a GUI.
    useGUI = true;
    if action == LOAD
        [fileName, pathName] = uigetfile('*.mat', 'Pick a Matlab project file to load.',pwd);
    elseif action == ADD
        [fileName, pathName] = uigetfile('*.mat', 'Pick a Matlab project file to add.',pwd);
    elseif action == SAVE
        [fileName, pathName] = uiputfile('*.mat', 'Pick a Matlab project file to save.',fullfile(pwd,'matproj.mat'));
    end
    
    if isa(fileName,'double')
        return;
    end
    fullName = fullfile(pathName,fileName);
else
    fullName = fullfile(fileName);
end

if action == LOAD || action == ADD
    % Save a backup of the current desktop.
    docHndl = matlab.desktop.editor.getAll();
    numFiles = length(docHndl);
    
    if numFiles > 0
        % Only save a backup if there are files open.
        disp([mfilename '.m--Saving backup of existing project...'])
        backupFileName = fullfile(prefdir,'matproj.bak.mat');
        numSaved = save_matproj(backupFileName,useGUI,docHndl);
        
        if numSaved < 0
            % save_matproj.m returns -1 if aborting.
            return;
        end
        
        if numSaved == 0
            disp([mfilename '.m--Backup of existing project NOT saved.'])
        else
            disp([mfilename '.m--Backup of existing project saved to ' backupFileName '.'])
        end
    end
    
    % Read in previously-saved project info.
    [~,~,ext] = fileparts(fullName);
    if strcmp(ext,'.mat')
        whoOut = who('-file',fullName);
        if ~ismember('matprojData',whoOut)
            error([mfilename '.m--Specified .mat file does not appear to contain matproj data.']);
        end
        load(fullName,'matprojData');
    else
        error([mfilename '.m--Specified file is not a .mat file.']);
    end
    
    if action == LOAD
        % Close existing project. This won't happen if action is ADD.
        docHndl = matlab.desktop.editor.getAll();
        numFiles = length(docHndl);
        for iFile = 1:numFiles
            docHndl(iFile).close;
        end
    end
    
    % Open previously-saved project.
    numFiles = length(matprojData.files);
    
    for iFile = 1:numFiles
        thisMatProjMember = matprojData.files(iFile);
        thisFileName = thisMatProjMember.Filename;
        thisSelection = thisMatProjMember.Selection;
        thisEditable = thisMatProjMember.Editable;
        
        % 2015-01-28--Thanks to David Brown for pointing this out. Loading
        % a project fails if it was saved with an unsaved "untitled" mfile
        % in it. Test to avoid the error.
        [thisFilePath,~,ext] = fileparts(thisFileName);
        if isempty(thisFilePath)
            warning([mfilename '.m--Skipping loading file ''' thisFileName ext ''' because no path information for it was found.']);
        else
            editorObj = matlab.desktop.editor.openDocument(thisFileName);
            
            if isempty(editorObj)
                warning([mfilename '.m--File ' thisFileName ' from loaded project was not found.']);
            else
                
                if isempty(thisSelection)
                    thisSelection = [1 1 1 1];
                end % end if isempty(thisSelection)
                
                editorObj.Selection = thisSelection;
                editorObj.Editable = thisEditable;
            end % if isempty(editorObj)
            
        end % if isempty thisFilePath
        
    end % for
    
    % Open the active document again to make it the current file.
    activeDocName = matprojData.activeDocName;
    
    if ~isempty(activeDocName)
        % ...Again, make sure this isn't an unsaved "untitled" document.
        [thisFilePath,~,ext] = fileparts(activeDocName);
        if ~isempty(thisFilePath)
            if ~isempty(activeDocName)
                editorObj = matlab.desktop.editor.openDocument(matprojData.activeDocName);
            end
        end
    end
    
    cd(matprojData.workingDir);
    
elseif action == SAVE
    if exist(fullName,'file')
        % uiputfile already handles overwrite dialogue, so only need case
        % for command-line interface.
        if ~useGUI
            r = input(['File ' fullName ' already exists. Overwrite? [Yes/No] '],'s');
            if ~strncmpi(r,'y',1)
                return;
            end
        end
    end
    numSaved = save_matproj(fullName,useGUI);
end
end

%-------------------------------------------------------------------------
function [numSaved] = save_matproj(outName,useGUI,varargin)
%
% save_matproj.m--Saves current project to named .mat file.
%-------------------------------------------------------------------------

if nargin>2
    docHndl = varargin{1};
else
    docHndl = matlab.desktop.editor.getAll();
end

numFiles = length(docHndl);

if numFiles == 0
    numSaved = 0;
end

if any(cat(1,docHndl.Modified))
    if useGUI
        warndlg('Unsaved edits exist in existing project. Aborting.', 'matproj', 'modal');
    else
        disp([mfilename '.m--Unsaved edits exist in existing project. Aborting.']);
    end
    numSaved = -1;
    return;
end

activeDoc = matlab.desktop.editor.getActive;
files = repmat(struct('Filename','','Selection',nan(1,4),'Editable',NaN),numFiles,1);

for iFile = 1:numFiles
    files(iFile).Filename = docHndl(iFile).Filename;
    files(iFile).Selection = docHndl(iFile).Selection;
    files(iFile).Editable = docHndl(iFile).Editable;
end

matprojData = struct();
matprojData.files = files;
matprojData.date = now;

if isempty(activeDoc)
    activeDocName = [];
else
    activeDocName = activeDoc.Filename;
end

matprojData.activeDocName = activeDocName;
matprojData.workingDir = pwd;
projPath = path;
matprojData.path = projPath;

save(outName,'matprojData');
numSaved = numFiles;

end