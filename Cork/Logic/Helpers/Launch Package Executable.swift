//
//  Launch Package Executable.swift
//  Cork
//
//  Created by Antigravity on 16.07.2026.
//

import Foundation
import CorkModels
import CorkShared
import CorkTerminalFunctions

public func runLaunchCommand(executablePath: String, arguments: String, packageName: String) throws -> Process?
{
    guard let resolvedURL = resolveExecutableURL(for: executablePath, packageName: packageName)
    else
    {
        AppConstants.shared.logger.error("Could not resolve executable: \(executablePath)")
        return nil
    }
    
    let args = arguments.components(separatedBy: .whitespaces).filter
    {
        !$0.isEmpty
    }
    
    let task = Process()
    var environment = ProcessInfo.processInfo.environment
    
    let brewBinPath = AppConstants.shared.brewExecutablePath.deletingLastPathComponent().path
    if let currentPath = environment["PATH"]
    {
        if !currentPath.contains(brewBinPath)
        {
            environment["PATH"] = "\(brewBinPath):\(currentPath)"
        }
    }
    else
    {
        environment["PATH"] = brewBinPath
    }
    
    task.environment = environment
    task.executableURL = resolvedURL
    task.arguments = args
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    
    ActiveProcessesRegistry.register(task)
    task.terminationHandler = { terminatedTask in
        ActiveProcessesRegistry.deregister(terminatedTask)
    }
    
    do
    {
        try task.run()
        return task
    }
    catch
    {
        AppConstants.shared.logger.error("Failed to run command \(executablePath): \(error.localizedDescription)")
        throw error
    }
}

public func resolveExecutableURL(for executableName: String, packageName: String) -> URL?
{
    let fm = FileManager.default
    
    // 0. Try absolute path
    if executableName.hasPrefix("/")
    {
        if fm.fileExists(atPath: executableName)
        {
            return URL(fileURLWithPath: executableName)
        }
    }
    
    // 1. Try standard brew bin directory
    let brewBinDir = AppConstants.shared.brewExecutablePath.deletingLastPathComponent()
    let standardURL = brewBinDir.appending(path: executableName)
    if fm.fileExists(atPath: standardURL.path)
    {
        return standardURL
    }
    
    // 2. Try cellar path
    let cellarPath = AppConstants.shared.brewCellarPath.appending(path: packageName)
    if fm.fileExists(atPath: cellarPath.path)
    {
        do
        {
            let contents = try fm.contentsOfDirectory(at: cellarPath, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for versionURL in contents
            {
                let cellerExecURL = versionURL.appending(path: "bin").appending(path: executableName)
                if fm.fileExists(atPath: cellerExecURL.path)
                {
                    return cellerExecURL
                }
            }
        }
        catch {}
    }
    
    return standardURL
}

public func discoverPackageExecutables(for package: BrewPackage) -> [String]
{
    var executables: [URL] = []
    
    guard package.type == .formula else { return [] }
    
    let fm = FileManager.default
    let cellarPath = AppConstants.shared.brewCellarPath.appending(path: package.name(withPrecision: .precise))
    
    guard fm.fileExists(atPath: cellarPath.path) else { return [] }
    
    do
    {
        let contents = try fm.contentsOfDirectory(at: cellarPath, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        for versionURL in contents
        {
            let binURL = versionURL.appending(path: "bin")
            if fm.fileExists(atPath: binURL.path)
            {
                let binContents = try fm.contentsOfDirectory(at: binURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                for fileURL in binContents
                {
                    if fm.isExecutableFile(atPath: fileURL.path)
                    {
                        executables.append(fileURL)
                    }
                }
            }
        }
    }
    catch
    {
        AppConstants.shared.logger.error("Failed to discover executables: \(error.localizedDescription)")
    }
    
    return Array(Set(executables.map { $0.lastPathComponent })).sorted()
}
