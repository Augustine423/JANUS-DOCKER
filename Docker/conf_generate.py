import tkinter as tk
from tkinter import messagebox
import os

def generate_janus_config(num_streams, output_file="janus.plugin.streaming.jcfg"):
    """
    Generate a Janus configuration file with a specified number of video streams.
    
    Args:
        num_streams (int): Number of video streams to generate (e.g., 1 to 1000).
        output_file (str): Name of the output configuration file.
    """
    if num_streams < 1 or num_streams > 1000:
        raise ValueError("Number of streams must be between 1 and 1000")

    config = f"""general: {{
    admin_key = "supersecret"
    events = true
    string_ids = false
}}

multistream-test: {{
    type = "rtp"
    id = 1234
    description = "Multistream test ({num_streams} video)"
    metadata = "This is an example of a multistream mountpoint: you'll get {num_streams} video feeds"
    secret = "adminpwd"
    media = (
"""

    for i in range(1, num_streams + 1):
        stream_id = f"v{i:03d}"
        port = 5000 + i
        label = str(5000 + i)
        recfile = f"/opt/janus/recordings/multistream-test-{stream_id}-%Y%m%d%H%M%S.mjr"
        
        media_entry = f"""        {{
            type = "video"
            mid = "{stream_id}"
            label = "{label}"
            port = {port}
            pt = 100
            codec = "h264"
            record = true
            recfile = "{recfile}"
        }}"""
        
        if i < num_streams:
            media_entry += ","
        
        config += media_entry + "\n"
    
    config += """    )
}
"""

    with open(output_file, 'w') as f:
        f.write(config)
    
    return output_file

def create_gui():
    def on_generate():
        try:
            num_streams = int(entry.get())
            output_file = generate_janus_config(num_streams)
            messagebox.showinfo("Success", f"Configuration file '{output_file}' generated with {num_streams} video streams.")
            entry.delete(0, tk.END)  # Clear the input field
        except ValueError as e:
            messagebox.showerror("Error", str(e))

    # Create the main window
    window = tk.Tk()
    window.title("Janus Config Generator")
    window.geometry("300x150")
    window.resizable(False, False)

    # Create and place widgets
    tk.Label(window, text="Number of Streams (1-1000):").pack(pady=10)
    
    entry = tk.Entry(window, width=20)
    entry.pack(pady=5)
    
    generate_button = tk.Button(window, text="Generate Config", command=on_generate)
    generate_button.pack(pady=10)

    # Start the main loop
    window.mainloop()

if __name__ == "__main__":
    create_gui()